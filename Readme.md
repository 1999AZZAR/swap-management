# Swap Manager - Enhanced

A powerful Linux swap management utility with intuitive UI for controlling ZRAM, ZSWAP, disk swap, and system parameters.

## Features

- **Modern Terminal UI** with color-coded output and intuitive menus
- **Swap Aggressiveness Control** with 3 presets + custom settings
- **ZRAM Management**:
  - Temporary or persistent configuration
  - Automatic size calculation based on RAM
- **ZSWAP Configuration**:
  - Compressor selection (lz4 by default)
  - Pool size adjustment
- **Disk Swap Management**:
  - Swap files and partitions
  - Safe removal procedure
- **Comprehensive Status Reports** with colored output
- **Auto Configuration** based on RAM multiplier (0.1x-3.0x)
- **System Parameter Optimization**:
  - Swappiness
  - Cache pressure
  - Dirty ratios

## Prerequisites

- **Root access** (required for swap operations)
- **Linux kernel** with:
  - ZRAM support (usually built-in)
  - ZSWAP support (check with `grep -i zswap /boot/config-$(uname -r)`)
- **systemd** (for persistent ZRAM service)
- **Basic utilities**: `bc`, `modprobe`, `mkswap`

## Installation

### Automated Installation

```bash
wget -q https://github.com/1999AZZAR/swap-management/raw/main/install.sh -O install.sh && bash install.sh
```

This will:
1. Install the script to `/usr/local/bin/swap-manager`
2. Create a `swap` alias for easy access
3. Set up logging and configuration directories

### Manual Installation

1. Download the script:

```bash
sudo wget -O /usr/local/bin/swap-manager https://raw.githubusercontent.com/1999AZZAR/swap-management/main/swap_manager.sh
```

2. Make it executable:

```bash
sudo chmod +x /usr/local/bin/swap-manager
```

3. (Optional) Create alias:

```bash
echo "alias swap='sudo swap-manager'" >> ~/.bashrc
source ~/.bashrc
```

## Usage

Run with:

```bash
sudo swap-manager
```

Or using the alias (if created):

```bash
swap
```

### Main Menu Overview

```
SWAP MEMORY MANAGEMENT SYSTEM
=====================================
 MAIN MENU
=====================================
  1) Auto Configuration
  2) Configure Swap Aggressiveness
  3) ZRAM Management
  4) ZSWAP Management
  5) Disk Swap Management
  6) Check System Status
  7) Exit
```

### Detailed Feature Breakdown

#### 1. Auto Configuration
- **1.5x RAM**: Balanced configuration (75% ZSWAP, 25% ZRAM)
- **2x RAM**: More aggressive swap allocation
- **Custom Multiplier**: Set any value between 0.1-3.0

*Example output during auto-configuration:*
```
Total RAM Size: 8192MB
Total Swap Size (1.5x RAM): 12288MB
Zswap Size (75%): 9216MB (9.00GB)
ZRAM Size (25%): 3072MB (3.00GB)
```

#### 2. Swap Aggressiveness
- **Presets**:
  - 🚀 Aggressive (100/200/5/3)
  - ⚖️ Moderate (60/100/20/10)
  - 🐢 Conservative (10/50/40/20)
- **Custom Settings**: Full control over all parameters

#### 3. ZRAM Management
- **Temporary Enable**: For current session only
- **Persistent Enable**: Creates systemd service
- **Disable**: Complete cleanup

#### 4. ZSWAP Management
- Toggle enabled/disabled state
- Configured via GRUB (requires reboot)

#### 5. Disk Swap Management
- **Add Swap**:
  - Files: Specify path and size (e.g., 2G)
  - Partitions: Select block device
- **Remove Swap**: Safely disable and clean up

#### 6. System Status
Comprehensive report including:
- Current RAM/swap usage
- ZRAM/ZSWAP status
- System parameters
- Configuration details

## Configuration Files

| Path | Purpose |
|------|---------|
| `/etc/swap-manager/` | Configuration directory |
| `/var/log/swap-manager.log` | Detailed operation log |
| `/etc/systemd/system/zram.service` | ZRAM service unit |

## Best Practices

### For Different System Types

1. **Memory-constrained systems** (e.g., Raspberry Pi):
   - Use Auto Config with 1.5x-2x multiplier
   - Aggressive preset recommended

2. **General desktop/laptop**:
   - Moderate preset
   - Consider 1x RAM for auto config

3. **Servers with abundant RAM**:
   - Conservative preset
   - Lower multipliers (0.5x-1x)

### Parameter Guidelines

| Parameter | Recommended Range | Effect |
|-----------|------------------|--------|
| Swappiness | 10-100 | Higher = more swapping |
| Cache Pressure | 50-200 | Higher = more cache reclaim |
| Dirty Ratio | 5-40 | Higher = more write caching |
| Dirty BG Ratio | 3-20 | Should be < Dirty Ratio |

## Troubleshooting

### Common Issues

**ZRAM not working**:
1. Check kernel module:
   ```bash
   lsmod | grep zram
   ```
2. Verify device:
   ```bash
   ls -l /dev/zram*
   ```

**ZSWAP not enabled after reboot**:
1. Check current parameters:
   ```bash
   cat /proc/cmdline | grep zswap
   ```
2. Verify module is loaded:
   ```bash
   lsmod | grep zswap
   ```

**Swap file creation fails**:
1. Check available space:
   ```bash
   df -h
   ```
2. Verify file creation:
   ```bash
   fallocate -l 1G testfile && rm testfile
   ```

### Viewing Logs

```bash
tail -f /var/log/swap-manager.log
```

## Safety Notes

⚠️ **Important Considerations**:
- Always test new configurations on non-critical systems first
- Monitor system stability after changes
- Reboot required for ZSWAP changes to take effect
- Extreme settings may cause system instability

## License

MIT License
