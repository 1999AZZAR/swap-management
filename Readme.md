# Swap Manager

A comprehensive Linux swap management utility that provides control over ZRAM, ZSWAP, disk swap, and system swap parameters.

## Features

- Swap aggressiveness control with presets
- ZRAM configuration and management
- ZSWAP setup and control
- Disk swap management
- System parameter optimization
- Comprehensive status reporting

## Prerequisites

- Root access
- Linux kernel with ZRAM and ZSWAP support
- systemd (for persistent ZRAM service)

## Installation

### manual

1. Copy `swap_manager.sh` to `/usr/local/bin/`:
   
   ```bash
   sudo cp swap_manager.sh /usr/local/bin/
   sudo chmod +x /usr/local/bin/swap_manager.sh
   ```

2. create an alias to make it more ease (optopnal):
   
   ```
   alias swap='sudo swap_manager.sh'
   ```

### Auto

Just run this command :

```bash
wget -q https://github.com/1999AZZAR/swap-management/raw/main/install.sh -O install.sh && bash install.sh
```

This command downloads and runs the installation script in one step

## Usage

Run the script as root:

```bash
sudo swap_manager.sh
```

or (if u created the alias (have been created when using the auto installer))

```bash
swap
```

### Menu Options

1. **Configure Swap Aggressiveness**
   
   - `a) Aggressive`: High swap usage (swappiness=100, cache_pressure=200)
   - `b) Moderate`: Balanced settings (swappiness=60, cache_pressure=100)
   - `c) Conservative`: Minimal swap usage (swappiness=10, cache_pressure=50)
   - `d) Custom`: Set your own parameters

2. **ZRAM Management**
   
   - `a) Enable (this session)`: Temporary ZRAM configuration
   - `b) Enable (persistent)`: Permanent ZRAM setup
   - `c) Disable`: Remove ZRAM configuration

3. **ZSWAP Management**
   
   - `a) Enable`: Configure and activate ZSWAP
   - `b) Disable`: Deactivate ZSWAP

4. **Disk Swap Management**
   
   - `a) Add swap`: Create swap file or partition
   - `b) Remove swap`: Disable and remove swap

5. **Check Status**: Display current system swap configuration

### System Parameters

- **Swappiness** (vm.swappiness)
  
  - Range: 0-100
  - Higher values: More aggressive swapping
  - Lower values: Prefer keeping processes in RAM

- **Cache Pressure** (vm.vfs_cache_pressure)
  
  - Range: 0-200
  - Higher values: More aggressive cache clearing
  - Lower values: Prefer keeping cache in RAM

- **Dirty Ratio** (vm.dirty_ratio)
  
  - Range: 0-100
  - Percentage of total RAM that can be dirty pages
  - Higher values: More write caching
  - Lower values: More frequent disk writes

- **Dirty Background Ratio** (vm.dirty_background_ratio)
  
  - Range: 0-100
  - Must be lower than dirty_ratio
  - Threshold for background writeback

## Presets

### Aggressive

- Swappiness: 100
- Cache Pressure: 200
- Dirty Ratio: 5
- Dirty Background Ratio: 3
- Best for: Systems with limited RAM

### Moderate

- Swappiness: 60
- Cache Pressure: 100
- Dirty Ratio: 20
- Dirty Background Ratio: 10
- Best for: General-purpose systems

### Conservative

- Swappiness: 10
- Cache Pressure: 50
- Dirty Ratio: 40
- Dirty Background Ratio: 20
- Best for: Systems with abundant RAM

## Configuration Files

- Config Directory: `/etc/swap-manager/`
- Log File: `/var/log/swap-manager.log`
- ZRAM Service: `/etc/systemd/system/zram.service`

## Troubleshooting

### Common Issues

1. **ZRAM fails to enable**
   
   - Check kernel module: `lsmod | grep zram`
   - Verify kernel support: `modinfo zram`

2. **ZSWAP not working**
   
   - Check kernel parameters: `cat /proc/cmdline`
   - Verify ZSWAP support: `cat /sys/module/zswap/parameters/enabled`

3. **Swap file creation fails**
   
   - Check available disk space: `df -h`
   - Verify filesystem support for swap files

### Logs

Check the log file for detailed error messages:

```bash
tail -f /var/log/swap-manager.log
```

## Safety Notes

- Always backup important data before modifying swap configuration
- Changes to GRUB parameters require system reboot
- Aggressive swap settings may impact system performance
- Monitor system behavior after changing settings

## License

MIT License
