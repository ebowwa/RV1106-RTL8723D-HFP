# RTL8723D Minimal Fix

## Problem
RTL8723D on RV1106 disconnects during HFP calls. Works at 1500000 baud, needs rtk_hciattach.

## Solution

### 1. Build rtk_hciattach (use GitHub Codespace)
```bash
cd tools/rtk_hciattach
./build.sh
```

### 2. Deploy to device
```bash
adb push rtk_hciattach /tmp/
adb shell "chmod +x /tmp/rtk_hciattach"
adb shell "/tmp/rtk_hciattach -n -s 115200 /dev/ttyS5 rtk_h5"
```

### 3. Start Bluetooth
```bash
adb shell "hciconfig hci0 up && bluealsa -p hfp-hf -p a2dp-sink &"
```

## Essential Files Only
- `/tools/rtk_hciattach/` - Build scripts
- `/RV1106-BlueFusion-HFP/rtk_hciattach_minimal.c` - Minimal implementation
- This file

That's it. Everything else is analysis/documentation.