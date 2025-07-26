# macOS to RV1106 RTL8723D Deployment Guide

## Overview
This guide documents the complete process of fixing RTL8723D Bluetooth HFP issues on RV1106 devices when developing on macOS.

## What We Accomplished

### 1. **Identified the Problem**
- RTL8723D on RV1106 disconnects during HFP (phone calls)
- A2DP (music) works fine
- Root cause: Missing Realtek-specific initialization tool

### 2. **Key Discoveries**
- Device operates at **1500000 baud** (not standard 115200)
- Firmware location: `/lib/firmware/rtlbt/`
- Required tool: `rtk_hciattach` (Realtek-specific)
- MAC address stays 00:00:00:00:00:00 without proper initialization

### 3. **Successfully Deployed rtk_hciattach**
- Compiled ARM binary using GitHub Codespaces
- Deployed to device via ADB
- Initialized RTL8723D with proper firmware
- MAC address changed from 00:00:00:00:00:00 to 34:75:63:40:51:3D

## GitHub Codespaces Solution for macOS

### Why Codespaces?
macOS cannot natively cross-compile for ARM Linux targets. GitHub Codespaces provides a Linux environment with ARM cross-compilation tools.

### Step-by-Step Process

#### 1. Create GitHub Repository
```bash
# From your Mac
cd /path/to/project
git init
git add .
git commit -m "Initial commit"
gh repo create RV1106-RTL8723D-HFP --public --push
```

#### 2. Open in GitHub Codespace
1. Go to https://github.com/YOUR_USERNAME/RV1106-RTL8723D-HFP
2. Click green "Code" button → "Codespaces" tab
3. Click "Create codespace on main"

#### 3. Build rtk_hciattach in Codespace
```bash
# In Codespace terminal
cd tools/rtk_hciattach
./build.sh
```

The build script automatically:
- Detects the Codespace environment
- Installs ARM cross-compiler: `gcc-arm-linux-gnueabihf`
- Compiles rtk_hciattach as static ARM binary
- Output: `ELF 32-bit LSB executable, ARM, EABI5`

#### 4. Download Binary
- In Codespace file explorer, navigate to `/tools/rtk_hciattach/`
- Right-click `rtk_hciattach` → "Download"
- File downloads to your Mac (may add .txt extension)

#### 5. Deploy to RV1106
```bash
# On your Mac
mv ~/Downloads/rtk_hciattach.txt ~/Downloads/rtk_hciattach
adb push ~/Downloads/rtk_hciattach /tmp/
adb shell "chmod +x /tmp/rtk_hciattach"
```

## Device Initialization Process

### 1. Run rtk_hciattach
```bash
adb shell "/tmp/rtk_hciattach -n -s 115200 /dev/ttyS5 rtk_h5"
```

### 2. What Happens
- Detects chip: RTL8723DS
- Loads firmware: rtl8723d_fw
- Loads config: rtl8723d_config
- Changes baud to 1500000
- Downloads 133 patches
- Sets proper MAC address

### 3. Verify Success
```bash
adb shell "hciconfig -a"
```

Should show:
- BD Address: Not 00:00:00:00:00:00
- Type: Primary Bus: UART
- Features enabled

## Build Configuration Details

### Codespace Build Environment
- Base image: Ubuntu Linux
- Required packages: `gcc-arm-linux-gnueabihf`
- Compiler flags: `-Wall -O2 -static`
- Target: ARM EABI5 32-bit

### Why Static Linking?
- No dependency issues on target device
- Works on minimal embedded systems
- Single binary deployment

## Troubleshooting

### If HCI0 stays DOWN
```bash
# Reset and retry
adb shell "hciconfig hci0 reset"
adb shell "sleep 1"
adb shell "hciconfig hci0 up"
```

### If BlueALSA fails
```bash
# Kill and restart
adb shell "killall bluealsa"
adb shell "bluealsa -p hfp-hf -p a2dp-sink &"
```

## Complete Solution Summary

1. **Problem**: RTL8723D HFP disconnections on RV1106
2. **Root Cause**: Missing rtk_hciattach initialization
3. **Solution**: Cross-compile rtk_hciattach using GitHub Codespaces
4. **Result**: Fully functional Bluetooth with HFP and A2DP

## Alternative Build Methods

### Docker (if Codespaces unavailable)
```bash
docker run --rm -v $PWD:/src arm32v7/gcc:9 \
  arm-linux-gnueabihf-gcc -o rtk_hciattach *.c
```

### Linux VM
- Install Ubuntu in VMware/VirtualBox
- Install: `sudo apt-get install gcc-arm-linux-gnueabihf`
- Compile as normal

### GitHub Actions
- Push to repo
- Workflow automatically builds
- Download artifact from Actions tab

## Key Files in Repository

- `/tools/rtk_hciattach/build.sh` - Automated build script
- `/tools/rtk_hciattach/*.c` - Source code
- `/.github/workflows/build-rtk-hciattach.yml` - CI/CD pipeline
- `/MINIMAL_SOLUTION.md` - Quick reference

This approach solves the cross-compilation challenge for macOS developers working with ARM embedded devices.