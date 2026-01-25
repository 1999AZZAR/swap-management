# Swap Manager - Enhanced

A powerful, safety-first Linux swap management utility with a modern terminal UI for controlling ZRAM, ZSWAP, disk swap, and system parameters.

## Features

- **Context-Aware Terminal UI**: Dynamic menus that adapt based on your system's current state (Enable/Disable toggles).
- **Proactive Dependency Check**: Validates required tools (`bc`, `mkswap`, etc.) on startup.
- **Advanced ZRAM Management**:
  - Temporary or persistent configuration via systemd.
  - **Live Algorithm Switching**: Detects and changes compression algorithms (lz4, zstd, etc.) on the fly.
  - Proactive module loading for algorithm discovery.
- **Robust ZSWAP Configuration**:
  - **Instant Runtime Updates**: Apply changes immediately via sysfs without rebooting.
  - **Crypto-API Integration**: Scans `/proc/crypto` to list only kernel-supported compressors.
  - Dual-layer persistence (Runtime + GRUB).
- **Disk Swap Suite**:
  - **Dynamic Resizing**: Safely resize swap files with data integrity checks.
  - **Priority Management**: Live and persistent swap priority control.
  - **Safety Guardrails**: Verifies `swapoff` success before file deletion; automatic `/etc/fstab` backups.
- **Swap Aggressiveness Control**: 3 optimized presets (Aggressive, Moderate, Conservative) + custom settings.
- **Auto-Configuration**: Intelligent RAM-based scaling (0.1x - 3.0x multiplier).

## Prerequisites

- **Root access** (Required for memory/swap operations)
- **Linux Kernel**: Support for ZRAM/ZSWAP
- **Core Utils**: `bc`, `modprobe`, `mkswap`, `fallocate`
- **Bootloader**: GRUB (for persistent ZSWAP settings)

## Installation

### Automated Installation

```bash
wget -q https://github.com/1999AZZAR/swap-management/raw/main/install.sh -O install.sh && bash install.sh
```

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
   echo "alias swap='sudo swap-manager'" >> ~/.bashrc && source ~/.bashrc
   ```

## Usage

Run the utility:

```bash
swap
```

### Main Menu Overview

1. **Auto Configuration**: Set recommended ZRAM/ZSWAP ratios based on RAM size.
2. **Configure Swap Aggressiveness**: Tune swappiness and cache pressure.
3. **ZRAM Management**: Toggle ZRAM and change compression algorithms.
4. **ZSWAP Management**: Context-aware toggle for ZSWAP and runtime compressor tuning.
5. **Disk Swap Management**: Add/Remove swap, change priority, or resize files.
6. **Check System Status**: Detailed report of RAM, ZRAM, ZSWAP, and Disk Swap.

## Configuration & Logs

| Path                               | Purpose                     |
| ---------------------------------- | --------------------------- |
| `/etc/swap-manager/`               | Configuration directory     |
| `/var/log/swap-manager.log`        | Operation logs for auditing |
| `/etc/systemd/system/zram.service` | Persistent ZRAM unit        |

## Safety Notes ⚠️

- **Memory Pressure**: Resizing or disabling swap during high memory usage may lead to OOM (Out of Memory) conditions.
- **Bootloader**: ZSWAP changes are applied to GRUB; ensure you verify bootloader updates if using a non-standard configuration.
- **Backups**: The script automatically backs up `/etc/fstab` before modifications.

## License

MIT License