# Ubuntu Mirror Smart Selector [🇮🇷 نسخه فارسی](README_FA.md)

An intelligent and high-performance script to automatically detect, test, and configure the best Ubuntu mirrors for your system.

## Overview

This script is specifically designed to help users find the fastest available Ubuntu repositories. It is particularly useful when **international internet access is restricted, unstable, or "nationalized" (Intranet/Melli)**, making global mirrors unreachable. By testing local (Iranian) and global mirrors, it ensures you can always update your system at the highest possible speed.

## Key Features

- **High-Performance Testing**: Measures both latency (ping) and real-world download speed.
- **Smart Scoring**: Uses a weighted formula (60% Latency, 40% Speed) to find the truly "best" mirror.
- **Iranian & Global Lists**: Pre-configured with a comprehensive list of top Iranian and international mirrors.
- **Sync Detection**: Automatically skips mirrors that are currently in the middle of a synchronization process.
- **Backup Manager**: Every change is backed up, allowing you to easily roll back to previous settings.
- **Modern Support**: Compatible with both legacy `sources.list` and the new DEB822 (`ubuntu.sources`) format used in newer Ubuntu versions (Noble 24.04+).

## Menu Options

1. **Iran only**: Tests only mirrors located within Iran. Ideal for times when international traffic is blocked or extremely slow.
2. **International only**: Tests standard global mirrors.
3. **Iran + International**: Checks everything and finds the absolute fastest one available to you.
4. **Test all and show top 5**: Instead of auto-applying, it shows you a ranked list of the top 5 mirrors for you to choose manually.
5. **Manage backups**: View all previous configurations and restore them with a single click.

## Usage

Simply run the script with root privileges:

```bash
wget https://raw.githubusercontent.com/alighaffari3000/mirror-smart/main/mirror-smart.sh
chmod +x mirror-smart.sh
sudo ./mirror-smart.sh
```

---
*Main description is in English as requested.*
