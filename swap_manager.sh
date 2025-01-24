#!/bin/bash

set -euo pipefail

# Configuration
readonly CONFIG_DIR="/etc/swap-manager"
readonly CONFIG_FILE="${CONFIG_DIR}/config.conf"
readonly LOG_FILE="/var/log/swap-manager.log"
readonly ZRAM_SERVICE="/etc/systemd/system/zram.service"

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
        log_error "Invalid size format. Use format like 1G, 2M, etc."
        return 1
    }
}

validate_path() {
    [[ -e $(dirname "$1") ]] || {
        log_error "Directory $(dirname "$1") does not exist"
        return 1
    }
}

validate_device() {
    [[ -b "$1" ]] || {
        log_error "Device $1 is not a valid block device"
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
    else
        # Use custom values
        swappiness=$1
        cache_pressure=$2
        dirty_ratio=$3
        dirty_bg_ratio=$4
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
    log_info "System parameters configured with mode: $mode"
}

# ZRAM management
configure_zram() {
    local size=$1
    validate_size "$size" || return 1

    modprobe zram
    echo "$size" >"/sys/block/zram0/disksize"
    mkswap "/dev/zram0"
    swapon "/dev/zram0"
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
ExecStart=/bin/bash -c 'modprobe zram && echo $size > /sys/block/zram0/disksize && mkswap /dev/zram0 && swapon /dev/zram0'
ExecStop=/bin/bash -c 'swapoff /dev/zram0 && rmmod zram'

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable zram.service
    log_info "ZRAM service created and enabled"
}

disable_zram() {
    swapoff "/dev/zram0" 2>/dev/null || true
    rmmod zram 2>/dev/null || true
    systemctl disable zram.service 2>/dev/null || true
    rm -f "$ZRAM_SERVICE"
    log_info "ZRAM disabled"
}

# ZSWAP management
configure_zswap() {
    local enabled=$1
    local compressor=${2:-$DEFAULT_ZSWAP_COMPRESSOR}
    local pool_percent=${3:-$DEFAULT_ZSWAP_MAX_POOL_PERCENT}
    local zpool=${4:-$DEFAULT_ZSWAP_ZPOOL}

    local params=""
    [[ "$enabled" == "true" ]] && params="zswap.enabled=1 zswap.compressor=$compressor zswap.max_pool_percent=$pool_percent zswap.zpool=$zpool"

    cp /etc/default/grub /etc/default/grub.backup
    sed -i "s/GRUB_CMDLINE_LINUX=\"\(.*\)\"/GRUB_CMDLINE_LINUX=\"\1 ${params}\"/" /etc/default/grub
    update-grub
    log_info "ZSWAP configuration updated. Reboot required."
}

# Disk swap management
configure_disk_swap() {
    local type=$1
    local location=$2
    local size=$3

    case "$type" in
    "partition")
        validate_device "$location" || return 1
        mkswap "$location"
        ;;
    "file")
        validate_path "$location" || return 1
        validate_size "$size" || return 1
        fallocate -l "$size" "$location"
        chmod 600 "$location"
        mkswap "$location"
        ;;
    *)
        log_error "Invalid swap type"
        return 1
        ;;
    esac

    swapon "$location"
    echo "$location none swap sw 0 0" >>/etc/fstab
    log_info "Disk swap configured: $location"
}

disable_disk_swap() {
    local location=$1
    swapoff "$location" 2>/dev/null || true
    sed -i "\|$location|d" /etc/fstab
    [[ -f "$location" ]] && rm -f "$location"
    log_info "Disk swap disabled: $location"
}

# Status reporting
check_status() {
    log_info "System Swap Status Report"
    echo "----------------------------------------"

    # ZRAM status
    if [[ -b "/dev/zram0" ]]; then
        echo "ZRAM: Enabled ($(cat /sys/block/zram0/disksize) bytes)"
    else
        echo "ZRAM: Disabled"
    fi

    # ZSWAP status
    if [[ -f "/sys/module/zswap/parameters/enabled" ]]; then
        echo "ZSWAP: $(cat /sys/module/zswap/parameters/enabled)"
        echo "Compressor: $(cat /sys/module/zswap/parameters/compressor)"
        echo "Pool: $(cat /sys/module/zswap/parameters/zpool)"
    else
        echo "ZSWAP: Not available"
    fi

    # System parameters
    echo -e "\nSystem Parameters:"
    sysctl vm.swappiness vm.vfs_cache_pressure vm.dirty_ratio vm.dirty_background_ratio

    # Swap devices
    echo -e "\nSwap Devices:"
    swapon --show || echo "No swap devices configured"
}

# Menu interface
show_menu() {
    cat <<EOF
Swap Management System
=====================
1. Configure Swap Aggressiveness
   a) Set Aggressive
   b) Set Moderate
   c) Set Conservative
   d) Custom Settings
2. ZRAM Management
   a) Enable (this session)
   b) Enable (persistent)
   c) Disable
3. ZSWAP Management
   a) Enable
   b) Disable
4. Disk Swap Management
   a) Add swap
   b) Remove swap
5. Check Status
6. Exit
=====================
EOF
}

# Main execution
main() {
    [[ $EUID -eq 0 ]] || {
        log_error "Must run as root"
        exit 1
    }
    mkdir -p "$CONFIG_DIR"
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"

    while true; do
        show_menu
        read -rp "Choose option: " choice
        case $choice in
        "1a") configure_sysctl_params "aggressive" ;;
        "1b") configure_sysctl_params "moderate" ;;
        "1c") configure_sysctl_params "conservative" ;;
        "1d")
            read -rp "Swappiness (0-100): " swappiness
            read -rp "Cache pressure (0-200): " cache_pressure
            read -rp "Dirty ratio (0-100): " dirty_ratio
            read -rp "Dirty background ratio (0-100): " dirty_bg_ratio
            configure_sysctl_params "$swappiness" "$cache_pressure" "$dirty_ratio" "$dirty_bg_ratio"
            ;;
        "2a" | "2b" | "2c")
            case ${choice:1} in
            a)
                read -rp "ZRAM size: " size
                configure_zram "$size"
                ;;
            b)
                read -rp "ZRAM size: " size
                configure_zram "$size" && create_zram_service "$size"
                ;;
            c) disable_zram ;;
            esac
            ;;
        "3a" | "3b")
            [[ ${choice:1} == "a" ]] && enabled="true" || enabled="false"
            configure_zswap "$enabled"
            ;;
        "4a" | "4b")
            if [[ ${choice:1} == "a" ]]; then
                read -rp "Type (partition/file): " type
                read -rp "Location: " location
                size=""
                [[ "$type" == "file" ]] && read -rp "Size: " size
                configure_disk_swap "$type" "$location" "$size"
            else
                read -rp "Location: " location
                disable_disk_swap "$location"
            fi
            ;;
        5) check_status ;;
        6)
            log_info "Exiting"
            exit 0
            ;;
        *) log_error "Invalid option" ;;
        esac
        echo
    done
}

main "$@"
