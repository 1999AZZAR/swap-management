#!/bin/bash

set -euo pipefail

# Configuration
readonly CONFIG_DIR="/etc/swap-manager"
readonly CONFIG_FILE="${CONFIG_DIR}/config.conf"
readonly LOG_FILE="/var/log/swap-manager.log"
readonly ZRAM_SERVICE="/etc/systemd/system/zram.service"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# UI Elements
readonly DIVIDER="$(printf '%*s\n' "$(tput cols)" '' | tr ' ' '=')"
readonly SMALL_DIVIDER="$(printf '%*s\n' "$(($(tput cols) / 2))" '' | tr ' ' '-')"

# Default values
readonly DEFAULT_ZSWAP_COMPRESSOR="lz4"
readonly DEFAULT_ZSWAP_MAX_POOL_PERCENT=50
readonly DEFAULT_ZSWAP_ZPOOL="z3fold"
readonly DEFAULT_SWAPPINESS=60
readonly DEFAULT_CACHE_PRESSURE=100
readonly DEFAULT_DIRTY_RATIO=20
readonly DEFAULT_DIRTY_BG_RATIO=10

# Swap aggressiveness presets
declare -A SWAP_PRESETS=(
    ["aggressive"]="swappiness=100 cache_pressure=200 dirty_ratio=5 dirty_bg_ratio=3"
    ["moderate"]="swappiness=60 cache_pressure=100 dirty_ratio=20 dirty_bg_ratio=10"
    ["conservative"]="swappiness=10 cache_pressure=50 dirty_ratio=40 dirty_bg_ratio=20"
)

# Helper functions
check_dependencies() {
    local dependencies=("bc" "mkswap" "swapon" "swapoff" "modprobe" "fallocate" "free" "sysctl")
    local missing_deps=()

    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_info "Please install them using your package manager."
        exit 1
    fi
}

print_header() {
    clear
    echo -e "${BLUE}$DIVIDER"
    echo -e " ${CYAN}SWAP MEMORY MANAGEMENT SYSTEM"
    echo -e "${BLUE}$DIVIDER${NC}"
}

print_menu_header() {
    echo -e "${YELLOW}$DIVIDER"
    echo -e " MAIN MENU"
    echo -e "$DIVIDER${NC}"
}

print_submenu_header() {
    local title=$1
    echo -e "${YELLOW}$SMALL_DIVIDER"
    echo -e " $title"
    echo -e "$SMALL_DIVIDER${NC}"
}

print_success() {
    echo -e "${GREEN}[✓] $1${NC}"
}

print_error() {
    echo -e "${RED}[✗] $1${NC}"
}

print_info() {
    echo -e "${CYAN}[i] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
}

press_enter_to_continue() {
    echo
    read -rp "Press Enter to continue..."
}

validate_input() {
    local prompt=$1
    local pattern=$2
    local error_msg=$3
    local input

    while true; do
        read -rp "$prompt" input
        if [[ $input =~ $pattern ]]; then
            echo "$input"
            return
        else
            print_error "$error_msg"
        fi
    done
}

# Logging functions
log() {
    local timestamp level message
    level="$1"
    shift
    message="$*"
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_error() { log "ERROR" "$@" >&2; }

error_handler() {
    log_error "Error (code: $2) occurred on line $1"
    exit "$2"
}

trap 'error_handler ${LINENO} $?' ERR

# Validation functions
validate_size() {
    local size=$1
    [[ $size =~ ^[0-9]+[GgMmKk]$ ]] || {
        print_error "Invalid size format. Use format like 1G, 2M, etc."
        return 1
    }
}

validate_path() {
    [[ -e $(dirname "$1") ]] || {
        print_error "Directory $(dirname "$1") does not exist"
        return 1
    }
}

validate_device() {
    [[ -b "$1" ]] || {
        print_error "Device $1 is not a valid block device"
        return 1
    }
}

# System parameter configuration
configure_sysctl_params() {
    local mode=$1

    if [[ -n "${SWAP_PRESETS[$mode]:-}" ]]; then
        # Parse preset values
        local preset="${SWAP_PRESETS[$mode]}"
        local swappiness cache_pressure dirty_ratio dirty_bg_ratio
        eval "$preset"
        print_info "Configuring system with $mode preset"
    else
        # Use custom values
        swappiness=$1
        cache_pressure=$2
        dirty_ratio=$3
        dirty_bg_ratio=$4
        print_info "Configuring system with custom parameters"
    fi

    local params=(
        "vm.swappiness=$swappiness"
        "vm.vfs_cache_pressure=$cache_pressure"
        "vm.dirty_ratio=$dirty_ratio"
        "vm.dirty_background_ratio=$dirty_bg_ratio"
    )

    for param in "${params[@]}"; do
        sysctl "$param"
        sed -i "/$param/d" /etc/sysctl.conf
        echo "$param" >>/etc/sysctl.conf
    done
    sysctl -p
    print_success "System parameters configured"
    log_info "System parameters configured: ${params[*]}"
}

# ZRAM management
configure_zram() {
    local size=$1
    validate_size "$size" || return 1

    # Clean up any existing ZRAM devices
    if [[ -b /dev/zram0 ]]; then
        swapoff /dev/zram0 2>/dev/null || true
        echo 1 >/sys/block/zram0/reset 2>/dev/null || true
    fi

    modprobe zram num_devices=1 || {
        print_error "Failed to load zram module"
        return 1
    }

    # Wait for device to be ready
    sleep 1

    echo "$size" >"/sys/block/zram0/disksize" || {
        print_error "Failed to set zram size"
        return 1
    }

    mkswap "/dev/zram0" || {
        print_error "Failed to create swap on zram"
        return 1
    }

    swapon "/dev/zram0" || {
        print_error "Failed to enable zram swap"
        return 1
    }

    print_success "ZRAM configured with size $size"
    log_info "ZRAM configured with size $size"
}

create_zram_service() {
    local size=$1
    cat >"$ZRAM_SERVICE" <<EOF
[Unit]
Description=ZRAM Setup
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'modprobe zram num_devices=1 && sleep 1 && echo $size > /sys/block/zram0/disksize && mkswap /dev/zram0 && swapon /dev/zram0'
ExecStop=/bin/bash -c 'swapoff /dev/zram0 && echo 1 > /sys/block/zram0/reset && rmmod zram'

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable zram.service
    print_success "ZRAM service created and enabled"
    log_info "ZRAM service created with size $size"
}

disable_zram() {
    swapoff "/dev/zram0" 2>/dev/null || true
    echo 1 >"/sys/block/zram0/reset" 2>/dev/null || true
    rmmod zram 2>/dev/null || true
    systemctl disable zram.service 2>/dev/null || true
    rm -f "$ZRAM_SERVICE"
    print_success "ZRAM disabled"
    log_info "ZRAM disabled"
}

# ZSWAP management
configure_zswap() {
    local enabled=$1
    local compressor=${2:-$DEFAULT_ZSWAP_COMPRESSOR}
    local pool_percent=${3:-$DEFAULT_ZSWAP_MAX_POOL_PERCENT}
    local zpool=${4:-$DEFAULT_ZSWAP_ZPOOL}

    local params=""
    if [[ "$enabled" == "true" ]]; then
        params="zswap.enabled=1 zswap.compressor=$compressor zswap.max_pool_percent=$pool_percent zswap.zpool=$zpool"
        print_info "Enabling ZSWAP with compressor: $compressor, max pool: $pool_percent%, pool type: $zpool"
        
        # Runtime configuration attempt
        if [[ -w /sys/module/zswap/parameters/enabled ]]; then
             # Try to set parameters first (ignore errors if some params are not writable or invalid)
             [[ -w /sys/module/zswap/parameters/compressor ]] && echo "$compressor" > /sys/module/zswap/parameters/compressor 2>/dev/null
             [[ -w /sys/module/zswap/parameters/max_pool_percent ]] && echo "$pool_percent" > /sys/module/zswap/parameters/max_pool_percent 2>/dev/null
             [[ -w /sys/module/zswap/parameters/zpool ]] && echo "$zpool" > /sys/module/zswap/parameters/zpool 2>/dev/null
             echo 1 > /sys/module/zswap/parameters/enabled 2>/dev/null
             print_info "Applied runtime ZSWAP configuration."
        fi
    else
        params="zswap.enabled=0"
        print_info "Disabling ZSWAP"
        
        # Runtime configuration attempt
        if [[ -w /sys/module/zswap/parameters/enabled ]]; then
             echo 0 > /sys/module/zswap/parameters/enabled 2>/dev/null
             print_info "Disabled ZSWAP in runtime."
        fi
    fi

    # Determine bootloader update command
    local update_cmd=""
    if command -v update-grub &>/dev/null; then
        update_cmd="update-grub"
    elif command -v grub2-mkconfig &>/dev/null; then
        update_cmd="grub2-mkconfig -o /boot/grub2/grub.cfg"
    elif command -v grub-mkconfig &>/dev/null; then
        update_cmd="grub-mkconfig -o /boot/grub/grub.cfg"
    else
        print_warning "No GRUB update command found. You may need to update your bootloader configuration manually."
    fi

    if [[ -f /etc/default/grub ]]; then
        cp /etc/default/grub /etc/default/grub.backup
        
        # Remove existing zswap parameters
        sed -i 's/zswap\.[^[:space:]"]*//g' /etc/default/grub
        
        # Add new parameters
        sed -i "s/GRUB_CMDLINE_LINUX=\"\(.*\)\"/GRUB_CMDLINE_LINUX=\"\1 ${params}\"/" /etc/default/grub
        
        # Clean up double spaces
        sed -i 's/  / /g' /etc/default/grub

        if [[ -n "$update_cmd" ]]; then
            print_info "Updating bootloader configuration..."
            eval "$update_cmd"
        fi
        
        print_success "ZSWAP configuration updated. Reboot required."
        log_info "ZSWAP configuration updated: $params"
    else
        print_error "/etc/default/grub not found. Cannot configure ZSWAP automatically."
        return 1
    fi
}

change_zswap_algorithm() {
    # Detect supported algorithms from kernel crypto API
    if [[ ! -f /proc/crypto ]]; then
        print_error "/proc/crypto not found. Cannot detect algorithms."
        return
    fi

    local current_algo
    current_algo=$(cat /sys/module/zswap/parameters/compressor 2>/dev/null || echo "unknown")

    print_info "Scanning kernel crypto modules for supported compression algorithms..."
    
    # Extract names associated with 'scomp' (synchronous compression) or 'compression' types
    local available_algos
    available_algos=$(awk '/type: scomp|type: compression/ {found=1} found && /name/ {print $3; found=0}' /proc/crypto | sort -u | tr '\n' ' ')

    if [[ -z "$available_algos" ]]; then
        print_warning "Could not auto-detect algorithms. Using common defaults."
        available_algos="lzo lz4 zstd lzo-rle 842"
    fi

    echo -e "${YELLOW}Available Algorithms:${NC}"
    echo "$available_algos" | tr ' ' '\n' | sed 's/^/  - /'
    echo -e "Current: ${GREEN}$current_algo${NC}"
    
    echo
    local choice
    read -rp "Enter algorithm name: " choice
    [[ -z "$choice" ]] && return

    # Validate input against available list (strict check)
    if ! echo "$available_algos" | grep -q "\b$choice\b"; then
        print_error "Algorithm '$choice' does not appear to be supported by your kernel."
        return
    fi

    # Runtime update
    if [[ -w /sys/module/zswap/parameters/compressor ]]; then
        print_info "Attempting runtime update..."
        
        # Check if ZSWAP is enabled
        local was_enabled=0
        if [[ $(cat /sys/module/zswap/parameters/enabled 2>/dev/null) == "Y" ]]; then
            was_enabled=1
        fi

        # We must often disable ZSWAP to change the compressor if pages are stored
        if [[ $was_enabled -eq 1 ]]; then
            echo 0 > /sys/module/zswap/parameters/enabled
        fi

        if echo "$choice" > /sys/module/zswap/parameters/compressor; then
            print_success "Runtime compressor updated to $choice"
        else
            print_error "Failed to update runtime compressor. It might be in use."
            # Try to restore enabled state if it failed
            [[ $was_enabled -eq 1 ]] && echo 1 > /sys/module/zswap/parameters/enabled
            return 1
        fi

        # Re-enable if it was enabled
        if [[ $was_enabled -eq 1 ]]; then
            echo 1 > /sys/module/zswap/parameters/enabled
        fi
    else
        print_warning "Runtime parameters not writable. Changes will only apply after reboot."
    fi

    # Persistent update (GRUB)
    print_info "Updating persistent configuration..."
    # We reuse configure_zswap but keep existing values for other params
    local pool_percent zpool
    pool_percent=$(cat /sys/module/zswap/parameters/max_pool_percent 2>/dev/null || echo "$DEFAULT_ZSWAP_MAX_POOL_PERCENT")
    zpool=$(cat /sys/module/zswap/parameters/zpool 2>/dev/null || echo "$DEFAULT_ZSWAP_ZPOOL")
    
    configure_zswap "true" "$choice" "$pool_percent" "$zpool"
}

# Disk swap management
configure_disk_swap() {
    local type=$1
    local location=$2
    local size=$3

    # Check if swap is already active
    if swapon --show | grep -q "$location"; then
        print_error "Swap at $location is already active"
        return 1
    fi

    # Check for existing fstab entry
    if grep -q "$location" /etc/fstab; then
        print_warning "Entry for $location already exists in /etc/fstab"
    fi

    case "$type" in
    "partition")
        validate_device "$location" || return 1
        
        # Confirm before formatting partition
        read -rp "WARNING: This will format $location. All data will be lost. Continue? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { print_info "Operation cancelled"; return 1; }
        
        mkswap "$location"
        ;;
    "file")
        validate_path "$location" || return 1
        validate_size "$size" || return 1
        
        if [[ -f "$location" ]]; then
            print_error "File $location already exists. Choose a different location or remove the file first."
            return 1
        fi
        
        # Check available disk space
        local dir_path=$(dirname "$location")
        local available_space=$(df -k --output=avail "$dir_path" | tail -n1)
        # Convert size string (e.g., 1G) to KB
        local size_kb
        if [[ "$size" =~ G$ ]]; then
            size_kb=$((${size%G} * 1024 * 1024))
        elif [[ "$size" =~ M$ ]]; then
            size_kb=$((${size%M} * 1024))
        fi
        
        if [[ $available_space -lt $size_kb ]]; then
            print_error "Insufficient disk space. Available: $((available_space/1024))MB, Required: $((size_kb/1024))MB"
            return 1
        fi

        print_info "Allocating swap file (this may take a moment)..."
        fallocate -l "$size" "$location"
        chmod 600 "$location"
        mkswap "$location"
        ;;
    *)
        print_error "Invalid swap type"
        return 1
        ;;
    esac

    swapon "$location"
    
    # Add to fstab if not present
    if ! grep -q "$location" /etc/fstab; then
        echo "$location none swap sw 0 0" >>/etc/fstab
    fi
    
    print_success "Disk swap configured: $location"
    log_info "Disk swap configured at $location with size ${size:-N/A}"
}

disable_disk_swap() {
    local location=$1
    
    if ! swapon --show | grep -q "$location"; then
        print_warning "Swap at $location is not active"
    else
        print_info "Disabling swap at $location..."
        if ! swapoff "$location"; then
            print_error "Failed to disable swap at $location. Operation aborted."
            return 1
        fi
    fi

    # Remove from fstab
    if grep -q "$location" /etc/fstab; then
        # Create backup of fstab
        cp /etc/fstab /etc/fstab.bak
        # Safe deletion using temporary file
        grep -v "$location" /etc/fstab > /etc/fstab.tmp && mv /etc/fstab.tmp /etc/fstab
        print_info "Removed entry from /etc/fstab"
    fi

    if [[ -f "$location" ]]; then
        read -rp "Do you want to delete the swap file $location? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm -f "$location"
            print_success "Swap file deleted"
        else
            print_info "Swap file kept at $location"
        fi
    fi
    
    print_success "Disk swap disabled: $location"
    log_info "Disk swap disabled at $location"
}

change_disk_swap_priority() {
    echo -e "\n${YELLOW}Active Swap Devices:${NC}"
    swapon --show --noheadings --output NAME,PRIO,TYPE | nl
    
    echo
    read -rp "Enter path of swap to modify (e.g., /swapfile): " location
    [[ -z "$location" ]] && return

    if ! swapon --show | grep -q "$location"; then
        print_error "Swap $location is not active"
        return
    fi

    local new_prio
    new_prio=$(validate_input "Enter new priority (-1 to 32767): " "^-?[0-9]+$" "Invalid integer")

    if ! swapoff "$location"; then
        print_error "Failed to disable swap. Cannot change priority."
        return
    fi

    # Update fstab if present
    if grep -q "$location" /etc/fstab; then
        # Remove existing pri option if present
        sed -i "s/,pri=[0-9-]*//g" /etc/fstab
        
        # Add new priority to the options
        if grep -q "$location.*sw" /etc/fstab; then
             sed -i "s|\($location.*sw\)|\1,pri=$new_prio|" /etc/fstab
        elif grep -q "$location.*defaults" /etc/fstab; then
             sed -i "s|\($location.*defaults\)|\1,pri=$new_prio|" /etc/fstab
        fi
    fi

    if swapon -p "$new_prio" "$location"; then
        print_success "Priority changed to $new_prio"
        log_info "Changed priority of $location to $new_prio"
    else
        print_error "Failed to re-enable swap"
        log_error "Failed to re-enable swap $location after priority change"
    fi
}

resize_disk_swap() {
    echo -e "\n${YELLOW}Active Swap Files:${NC}"
    swapon --show --noheadings --output NAME,TYPE,SIZE | grep "file" | nl
    
    echo
    read -rp "Enter path of swap file to resize: " location
    [[ -z "$location" ]] && return

    if [[ ! -f "$location" ]]; then
        print_error "File not found or not a regular file"
        return
    fi

    local current_size
    current_size=$(du -h "$location" | cut -f1)
    print_info "Current size: $current_size"

    local new_size
    new_size=$(validate_input "Enter new size (e.g., 2G, 512M): " "^[0-9]+[GgMmKk]$" "Invalid format")

    print_warning "This involves disabling swap, which may fail if memory is full."
    read -rp "Continue? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || return

    if ! swapoff "$location"; then
        print_error "Failed to disable swap. Aborting resize."
        return
    fi

    print_info "Resizing..."
    if ! fallocate -l "$new_size" "$location"; then
        print_error "Failed to resize file. Restoring old swap..."
        mkswap "$location" &>/dev/null
        swapon "$location"
        return 1
    fi

    chmod 600 "$location"
    if ! mkswap "$location"; then
         print_error "Failed to format swap. File may be corrupted."
         return 1
    fi

    if swapon "$location"; then
        print_success "Swap resized to $new_size"
        log_info "Resized swap file $location to $new_size"
    else
        print_error "Failed to re-enable swap"
    fi
}

# Auto-configuration based on RAM size
auto_configure_swap() {
    local multiplier=$1

    # Validate multiplier is within range
    if (($(echo "$multiplier < 0.1" | bc -l))) || (($(echo "$multiplier > 3" | bc -l))); then
        print_error "Multiplier must be between 0.1 and 3"
        return 1
    fi

    # Detect total RAM in MB
    RAM_SIZE_MB=$(free -m | awk '/^Mem:/ { print $2 }')

    # Calculate total memory for Zswap and ZRAM (multiplier * RAM size)
    TOTAL_SWAP_SIZE_MB=$(echo "$RAM_SIZE_MB * $multiplier" | bc | cut -d. -f1)

    # Calculate 75% for Zswap and 25% for ZRAM
    ZSWAP_SIZE_MB=$(echo "$TOTAL_SWAP_SIZE_MB * 0.75" | bc | cut -d. -f1)
    ZRAM_SIZE_MB=$(echo "$TOTAL_SWAP_SIZE_MB * 0.25" | bc | cut -d. -f1)

    # Convert sizes to GB
    ZSWAP_SIZE_GB=$(echo "scale=2; $ZSWAP_SIZE_MB / 1024" | bc)
    ZRAM_SIZE_GB=$(echo "scale=2; $ZRAM_SIZE_MB / 1024" | bc)

    echo -e "${CYAN}System Information:${NC}"
    echo -e "Total RAM Size: ${YELLOW}${RAM_SIZE_MB}MB${NC}"
    echo -e "Total Swap Size (${multiplier}x RAM): ${YELLOW}${TOTAL_SWAP_SIZE_MB}MB${NC}"
    echo -e "Zswap Size (75%): ${YELLOW}${ZSWAP_SIZE_MB}MB (${ZSWAP_SIZE_GB}GB)${NC}"
    echo -e "ZRAM Size (25%): ${YELLOW}${ZRAM_SIZE_MB}MB (${ZRAM_SIZE_GB}GB)${NC}"

    # Clean up any existing ZRAM configuration
    if [[ -b /dev/zram0 ]]; then
        print_info "Cleaning up existing ZRAM configuration..."
        swapoff /dev/zram0 2>/dev/null || true
        echo 1 >/sys/block/zram0/reset 2>/dev/null || true
    fi

    # Check if ZRAM is already loaded
    if ! lsmod | grep -q zram; then
        print_info "Loading ZRAM module..."
        modprobe zram num_devices=1 || {
            print_error "Failed to load zram module"
            return 1
        }
        sleep 1
    fi

    # Configure ZRAM
    print_info "Configuring ZRAM with size ${ZRAM_SIZE_MB}M..."
    echo "${ZRAM_SIZE_MB}M" >/sys/block/zram0/disksize || {
        print_error "Failed to set zram size"
        return 1
    }

    mkswap /dev/zram0 || {
        print_error "Failed to create swap on zram"
        return 1
    }

    swapon /dev/zram0 || {
        print_error "Failed to enable zram swap"
        return 1
    }

    # Configure Zswap
    print_info "Configuring Zswap with max_pool_percent: 75"
    echo "75" >/sys/module/zswap/parameters/max_pool_percent
    echo "1" >/sys/module/zswap/parameters/enabled

    # Display current swap status
    echo -e "\n${CYAN}Current Swap Status:${NC}"
    swapon --show

    print_success "ZRAM and Zswap setup complete!"
    log_info "Auto-configured swap based on RAM size of ${RAM_SIZE_MB}MB with multiplier ${multiplier}x"
}

# Status reporting
check_status() {
    log_info "System Swap Status Report"
    echo -e "${CYAN}$DIVIDER"
    echo -e " SYSTEM SWAP STATUS REPORT"
    echo -e "$DIVIDER${NC}"

    # RAM info
    RAM_SIZE_MB=$(free -m | awk '/^Mem:/ { print $2 }')
    RAM_SIZE_GB=$(echo "scale=2; $RAM_SIZE_MB / 1024" | bc)
    echo -e "${YELLOW}RAM Information:${NC}"
    echo -e "Total: ${RAM_SIZE_MB}MB (${RAM_SIZE_GB}GB)"
    echo -e "Used: $(free -m | awk '/^Mem:/ { print $3 }')MB"
    echo -e "Free: $(free -m | awk '/^Mem:/ { print $4 }')MB"

    # Swap files/partitions (excluding zram)
    echo -e "\n${YELLOW}Swap Devices (excluding zram):${NC}"
    DISK_SWAP_INFO=$(swapon --show --bytes | grep -v zram || echo "None")
    echo "$DISK_SWAP_INFO"

    # Calculate total disk swap
    if [[ "$DISK_SWAP_INFO" != "None" ]]; then
        DISK_SWAP_BYTES=$(echo "$DISK_SWAP_INFO" | awk '{sum += $3} END {print sum}')
        DISK_SWAP_MB=$((DISK_SWAP_BYTES / 1024 / 1024))
        DISK_SWAP_GB=$(echo "scale=2; $DISK_SWAP_MB / 1024" | bc)
        echo -e "Total Disk Swap: ${DISK_SWAP_MB}MB (${DISK_SWAP_GB}GB)"
    fi

    # ZRAM status
    echo -e "\n${YELLOW}ZRAM Status:${NC}"
    if [[ -b "/dev/zram0" ]]; then
        ZRAM_SIZE_BYTES=$(cat /sys/block/zram0/disksize)
        ZRAM_SIZE_MB=$((ZRAM_SIZE_BYTES / 1024 / 1024))
        ZRAM_SIZE_GB=$(echo "scale=2; $ZRAM_SIZE_MB / 1024" | bc)
        ZRAM_USED=$(grep zram /proc/swaps 2>/dev/null | awk '{print $4}' || echo "0")

        echo -e "Status: ${GREEN}Enabled${NC}"
        echo -e "Size: ${ZRAM_SIZE_MB}MB (${ZRAM_SIZE_GB}GB)"
        echo -e "Used: ${ZRAM_USED}KB"
        echo -e "Compression Algorithm: $(cat /sys/block/zram0/comp_algorithm 2>/dev/null | grep -o '\[.*\]' | tr -d '[]' 2>/dev/null || echo "Unknown")"

        if [[ -f "/sys/block/zram0/mm_stat" ]]; then
            echo -e "Memory Used for Pages: $(awk '{print $1}' /sys/block/zram0/mm_stat) bytes"
            echo -e "Compressed Data Size: $(awk '{print $3}' /sys/block/zram0/mm_stat) bytes"
        fi
    else
        echo -e "Status: ${RED}Disabled${NC}"
    fi

    # ZSWAP status
    echo -e "\n${YELLOW}ZSWAP Status:${NC}"
    if [[ -d "/sys/module/zswap" ]]; then
        echo -e "Enabled: $(cat /sys/module/zswap/parameters/enabled 2>/dev/null || echo "Unknown")"
        echo -e "Compressor: $(cat /sys/module/zswap/parameters/compressor 2>/dev/null || echo "Unknown")"
        echo -e "Max Pool Percent: $(cat /sys/module/zswap/parameters/max_pool_percent 2>/dev/null || echo "Unknown")"
        echo -e "Pool Type: $(cat /sys/module/zswap/parameters/zpool 2>/dev/null || echo "Unknown")"

        if [[ -d "/sys/kernel/debug/zswap" ]]; then
            echo -e "Stored Pages: $(cat /sys/kernel/debug/zswap/stored_pages 2>/dev/null || echo "Unknown")"
            echo -e "Pool Size: $(cat /sys/kernel/debug/zswap/pool_total_size 2>/dev/null || echo "Unknown") bytes"
        fi
    else
        echo -e "Status: ${RED}Not available${NC}"
    fi

    # System parameters
    echo -e "\n${YELLOW}System Parameters:${NC}"
    sysctl vm.swappiness vm.vfs_cache_pressure vm.dirty_ratio vm.dirty_background_ratio

    # Swap summary
    echo -e "\n${YELLOW}Swap Summary:${NC}"
    swapon --summary

    # Total swap (all types)
    TOTAL_SWAP_KB=$(free | grep "Swap:" | awk '{print $2}')
    TOTAL_SWAP_MB=$((TOTAL_SWAP_KB / 1024))
    TOTAL_SWAP_GB=$(echo "scale=2; $TOTAL_SWAP_MB / 1024" | bc)
    SWAP_USED_KB=$(free | grep "Swap:" | awk '{print $3}')
    SWAP_USED_MB=$((SWAP_USED_KB / 1024))
    SWAP_USED_GB=$(echo "scale=2; $SWAP_USED_MB / 1024" | bc)

    echo -e "\n${YELLOW}Total Swap (all types):${NC} ${TOTAL_SWAP_MB}MB (${TOTAL_SWAP_GB}GB)"
    echo -e "${YELLOW}Swap Used:${NC} ${SWAP_USED_MB}MB (${SWAP_USED_GB}GB)"

    # Calculate RAM-to-Swap ratio
    SWAP_RATIO=$(echo "scale=2; $TOTAL_SWAP_MB / $RAM_SIZE_MB" | bc)
    echo -e "${YELLOW}RAM-to-Swap Ratio:${NC} ${SWAP_RATIO}x RAM"
}

# Menu functions
show_auto_config_menu() {
    while true; do
        print_header
        print_submenu_header "AUTO CONFIGURATION"
        echo -e "  ${GREEN}1)${NC} 1.5x RAM configuration"
        echo -e "  ${GREEN}2)${NC} 2x RAM configuration"
        echo -e "  ${GREEN}3)${NC} Custom multiplier (0.1-3.0)"
        echo -e "  ${RED}4)${NC} Back to main menu"
        echo

        local choice
        choice=$(validate_input "Select option [1-4]: " "^[1-4]$" "Please enter a number between 1 and 4")

        case $choice in
        1) auto_configure_swap 1.5 ;;
        2) auto_configure_swap 2.0 ;;
        3)
            local multiplier
            multiplier=$(validate_input "Enter RAM multiplier (0.1-3.0): " "^[0-9]*\.?[0-9]+$" "Invalid number")
            auto_configure_swap "$multiplier"
            ;;
        4) return ;;
        esac

        press_enter_to_continue
    done
}

show_aggressiveness_menu() {
    while true; do
        print_header
        print_submenu_header "SWAP AGGRESSIVENESS"
        echo -e "  ${GREEN}1)${NC} Aggressive (swappiness=100, cache=200)"
        echo -e "  ${GREEN}2)${NC} Moderate (swappiness=60, cache=100)"
        echo -e "  ${GREEN}3)${NC} Conservative (swappiness=10, cache=50)"
        echo -e "  ${GREEN}4)${NC} Custom settings"
        echo -e "  ${RED}5)${NC} Back to main menu"
        echo

        local choice
        choice=$(validate_input "Select option [1-5]: " "^[1-5]$" "Please enter a number between 1 and 5")

        case $choice in
        1) configure_sysctl_params "aggressive" ;;
        2) configure_sysctl_params "moderate" ;;
        3) configure_sysctl_params "conservative" ;;
        4)
            local swappiness cache_pressure dirty_ratio dirty_bg_ratio
            swappiness=$(validate_input "Swappiness (0-100): " "^[0-9]{1,3}$" "Invalid value (0-100)")
            cache_pressure=$(validate_input "Cache pressure (0-200): " "^[0-9]{1,3}$" "Invalid value (0-200)")
            dirty_ratio=$(validate_input "Dirty ratio (0-100): " "^[0-9]{1,3}$" "Invalid value (0-100)")
            dirty_bg_ratio=$(validate_input "Dirty background ratio (0-100): " "^[0-9]{1,3}$" "Invalid value (0-100)")
            configure_sysctl_params "$swappiness" "$cache_pressure" "$dirty_ratio" "$dirty_bg_ratio"
            ;;
        5) return ;;
        esac

        press_enter_to_continue
    done
}

change_zram_algorithm() {
    # If module is not loaded, load it to see available algorithms
    if ! lsmod | grep -q zram; then
        print_info "Loading ZRAM module to detect supported algorithms..."
        modprobe zram num_devices=1 || {
            print_error "Failed to load zram module."
            return
        }
        sleep 1
    fi

    local dev="/dev/zram0"
    local algos_file="/sys/block/zram0/comp_algorithm"
    
    if [[ ! -f "$algos_file" ]]; then
        print_error "ZRAM sysfs interface not found at $algos_file"
        return
    fi

    local current_algos
    current_algos=$(cat "$algos_file")
    # Clean up the output to show which one is selected
    echo -e "${YELLOW}Available Algorithms (current in brackets):${NC}"
    echo "$current_algos"
    
    echo
    local choice
    read -rp "Enter algorithm name (e.g., lz4, zstd, lzo): " choice
    
    if [[ -z "$choice" ]]; then return; fi
    
    # Check if choice is in available algos (literal check)
    if ! echo "$current_algos" | grep -q "\b$choice\b"; then
        print_error "Algorithm '$choice' not supported by your kernel."
        return
    fi

    # Check if currently active
    local was_active=false
    if swapon --show | grep -q "$dev"; then
        was_active=true
        print_info "ZRAM is currently active. Disabling to change algorithm..."
        if ! swapoff "$dev"; then
            print_error "Failed to disable ZRAM. Algorithm change aborted."
            return
        fi
    fi
    
    # Reset and apply
    print_info "Applying algorithm $choice..."
    echo 1 > /sys/block/zram0/reset 2>/dev/null || true
    if ! echo "$choice" > "$algos_file"; then
        print_error "Failed to set algorithm. It might be in use or unsupported."
        return
    fi
    
    # If it was active, re-enable it. If not, just leave it with the new algo set.
    if [[ "$was_active" == "true" ]]; then
        local ram_mb
        ram_mb=$(free -m | awk '/^Mem:/ { print $2 }')
        local default_size="$((ram_mb / 4))M"
        
        print_info "Re-enabling ZRAM..."
        echo "$default_size" > /sys/block/zram0/disksize
        mkswap "$dev" >/dev/null
        swapon "$dev"
        print_success "ZRAM re-enabled with $choice compression."
    else
        print_success "ZRAM compression algorithm set to $choice. It will be used next time ZRAM is enabled."
    fi
}

show_zram_menu() {
    while true; do
        print_header
        print_submenu_header "ZRAM MANAGEMENT"
        
        # Check if ZRAM is active
        local is_active=false
        if swapon --show | grep -q "/dev/zram0"; then
            is_active=true
        fi

        if [[ "$is_active" == "true" ]]; then
            echo -e "  ${RED}1)${NC} Disable ZRAM"
            echo -e "  ${GREEN}2)${NC} Change Compression Algorithm"
            echo -e "  ${RED}3)${NC} Back to main menu"
            
            local choice
            choice=$(validate_input "Select option [1-3]: " "^[1-3]$" "Please enter a number between 1 and 3")
            
            case $choice in
            1) disable_zram ;;
            2) change_zram_algorithm ;;
            3) return ;;
            esac
        else
            echo -e "  ${GREEN}1)${NC} Enable ZRAM (current session)"
            echo -e "  ${GREEN}2)${NC} Enable ZRAM (persistent)"
            echo -e "  ${GREEN}3)${NC} Change Compression Algorithm"
            echo -e "  ${RED}4)${NC} Back to main menu"
            
            local choice
            choice=$(validate_input "Select option [1-4]: " "^[1-4]$" "Please enter a number between 1 and 4")
            
            case $choice in
            1)
                local size
                size=$(validate_input "Enter ZRAM size (e.g., 1G, 2M): " "^[0-9]+[GgMmKk]$" "Invalid size format")
                configure_zram "$size"
                ;;
            2)
                local size
                size=$(validate_input "Enter ZRAM size (e.g., 1G, 2M): " "^[0-9]+[GgMmKk]$" "Invalid size format")
                configure_zram "$size" && create_zram_service "$size"
                ;;
            3) change_zram_algorithm ;;
            4) return ;;
            esac
        fi

        press_enter_to_continue
    done
}

show_zswap_menu() {
    while true; do
        print_header
        print_submenu_header "ZSWAP MANAGEMENT"
        
        local zswap_state="N"
        if [[ -f "/sys/module/zswap/parameters/enabled" ]]; then
            zswap_state=$(cat /sys/module/zswap/parameters/enabled)
        fi

        if [[ "$zswap_state" == "Y" ]]; then
             echo -e "  ${RED}1)${NC} Disable ZSWAP"
             echo -e "  ${GREEN}2)${NC} Change Compression Algorithm"
             echo -e "  ${RED}3)${NC} Back to main menu"
             
             local choice
             choice=$(validate_input "Select option [1-3]: " "^[1-3]$" "Please enter a number between 1 and 3")

             case $choice in
             1) configure_zswap "false" ;;
             2) change_zswap_algorithm ;;
             3) return ;;
             esac
        else
             echo -e "  ${GREEN}1)${NC} Enable ZSWAP (Default)"
             echo -e "  ${GREEN}2)${NC} Enable ZSWAP (Custom)"
             echo -e "  ${RED}3)${NC} Back to main menu"
             
             local choice
             choice=$(validate_input "Select option [1-3]: " "^[1-3]$" "Please enter a number between 1 and 3")

             case $choice in
             1) configure_zswap "true" ;;
             2) 
                local compressor pool_percent zpool
                # Get current values or defaults
                local cur_comp=$(cat /sys/module/zswap/parameters/compressor 2>/dev/null || echo "$DEFAULT_ZSWAP_COMPRESSOR")
                local cur_pool=$(cat /sys/module/zswap/parameters/max_pool_percent 2>/dev/null || echo "$DEFAULT_ZSWAP_MAX_POOL_PERCENT")
                local cur_zpool=$(cat /sys/module/zswap/parameters/zpool 2>/dev/null || echo "$DEFAULT_ZSWAP_ZPOOL")
                
                # Pre-scan for compressors to show user what's available
                print_info "Scanning supported algorithms..."
                local available_algos
                if [[ -f /proc/crypto ]]; then
                     available_algos=$(awk '/type: scomp|type: compression/ {found=1} found && /name/ {print $3; found=0}' /proc/crypto | sort -u | tr '\n' ' ')
                fi
                echo -e "${YELLOW}Available:${NC} ${available_algos:-lzo lz4 zstd}"
                
                read -rp "Compressor (default: $cur_comp): " compressor
                [[ -z "$compressor" ]] && compressor=$cur_comp
                
                read -rp "Max Pool Percent (default: $cur_pool): " pool_percent
                [[ -z "$pool_percent" ]] && pool_percent=$cur_pool
                
                read -rp "Zpool allocator (default: $cur_zpool): " zpool
                [[ -z "$zpool" ]] && zpool=$cur_zpool
                
                configure_zswap "true" "$compressor" "$pool_percent" "$zpool"
                ;;
             3) return ;;
             esac
        fi

        press_enter_to_continue
    done
}

show_disk_swap_menu() {
    while true; do
        print_header
        print_submenu_header "DISK SWAP MANAGEMENT"
        echo -e "  ${GREEN}1)${NC} Add swap"
        echo -e "  ${GREEN}2)${NC} Remove swap"
        echo -e "  ${GREEN}3)${NC} Change swap priority"
        echo -e "  ${GREEN}4)${NC} Resize swap file"
        echo -e "  ${RED}5)${NC} Back to main menu"
        echo

        local choice
        choice=$(validate_input "Select option [1-5]: " "^[1-5]$" "Please enter a number between 1 and 5")

        case $choice in
        1)
            local type location size
            type=$(validate_input "Type (partition/file): " "^(partition|file)$" "Must be 'partition' or 'file'")
            read -rp "Location: " location
            if [[ "$type" == "file" ]]; then
                size=$(validate_input "Size (e.g., 1G, 2M): " "^[0-9]+[GgMmKk]$" "Invalid size format")
            fi
            configure_disk_swap "$type" "$location" "$size"
            ;;
        2)
            echo -e "\n${YELLOW}Active Swap Devices:${NC}"
            swapon --show --noheadings --output NAME,TYPE,SIZE | nl
            
            echo
            read -rp "Enter path of swap to remove (or leave empty to cancel): " location
            if [[ -n "$location" ]]; then
                disable_disk_swap "$location"
            fi
            ;;
        3) change_disk_swap_priority ;;
        4) resize_disk_swap ;;
        5) return ;;
        esac

        press_enter_to_continue
    done
}

# Main menu
show_main_menu() {
    while true; do
        print_header
        print_menu_header
        echo -e "  ${GREEN}1)${NC} Auto Configuration"
        echo -e "  ${GREEN}2)${NC} Configure Swap Aggressiveness"
        echo -e "  ${GREEN}3)${NC} ZRAM Management"
        echo -e "  ${GREEN}4)${NC} ZSWAP Management"
        echo -e "  ${GREEN}5)${NC} Disk Swap Management"
        echo -e "  ${GREEN}6)${NC} Check System Status"
        echo -e "  ${RED}7)${NC} Exit"
        echo

        local choice
        choice=$(validate_input "Select option [1-7]: " "^[1-7]$" "Please enter a number between 1 and 7")

        case $choice in
        1) show_auto_config_menu ;;
        2) show_aggressiveness_menu ;;
        3) show_zram_menu ;;
        4) show_zswap_menu ;;
        5) show_disk_swap_menu ;;
        6)
            check_status
            press_enter_to_continue
            ;;
        7)
            print_info "Exiting Swap Memory Manager"
            exit 0
            ;;
        esac
    done
}

# Main execution
main() {
    [[ $EUID -eq 0 ]] || {
        print_error "Must run as root"
        exit 1
    }
    
    check_dependencies
    
    mkdir -p "$CONFIG_DIR"
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"

    show_main_menu
}

main "$@"
