# RTL8723D on RV1106 - Final Solution

## ✅ What We Discovered

1. **The RTL8723D chip is working** - it responds at 1500000 baud (not the standard 115200)
2. **Firmware files are present** at `/lib/firmware/rtlbt/`
3. **The chip receives HCI commands** (RX bytes: 2775)
4. **MAC address remains 00:00:00:00:00:00** without proper initialization

## 🔧 The Solution

The RTL8723D requires the Realtek-specific `rtk_hciattach` tool to:
- Load firmware into the chip
- Set the proper MAC address
- Enable HFP and A2DP profiles

## 📱 For macOS Development

Since you're developing on macOS for an ARM board, here are your options:

### Option 1: Use Pre-built Binary
```bash
# Download from Radxa repository
wget https://github.com/radxa/rkwifibt/raw/master/realtek/rtk_hciattach/rtk_hciattach_arm
adb push rtk_hciattach_arm /tmp/rtk_hciattach
adb shell "chmod +x /tmp/rtk_hciattach"
adb shell "/tmp/rtk_hciattach -n -s 115200 /dev/ttyS5 rtk_h5"
```

### Option 2: Use Linux VM/Cloud
1. Spin up an Ubuntu VM or use a cloud Linux instance
2. Install ARM cross-compiler: `sudo apt-get install gcc-arm-linux-gnueabihf`
3. Clone and compile:
   ```bash
   git clone https://github.com/seuscq/rtk_hciattach.git
   cd rtk_hciattach
   arm-linux-gnueabihf-gcc -o rtk_hciattach hciattach.c hciattach_rtk.c
   ```

### Option 3: Use GitHub Actions
Create a workflow to build for ARM and download the artifact.

## 🚀 Once You Have rtk_hciattach

```bash
# Push to device
adb push rtk_hciattach /tmp/

# Make executable
adb shell "chmod +x /tmp/rtk_hciattach"

# Initialize RTL8723D
adb shell "/tmp/rtk_hciattach -n -s 115200 /dev/ttyS5 rtk_h5"

# Verify initialization
adb shell "hciconfig -a"

# Start BlueALSA for HFP/A2DP
adb shell "bluealsa -p hfp-hf -p a2dp-sink &"
```

## 📊 Expected Results

After proper initialization:
- MAC address will change from 00:00:00:00:00:00 to actual address
- HCI interface will be fully functional
- HFP (phone calls) and A2DP (music) will work

## 🔄 Current Workaround

While you get rtk_hciattach, you can partially use the device:

```bash
adb shell "hciattach /dev/ttyS5 any 1500000 flow noflow &"
adb shell "hciconfig hci0 up"
```

This gives limited functionality but won't load firmware or set MAC address.

## 📝 Summary

The hardware is working perfectly - it just needs the Realtek-specific initialization tool. Once you run `rtk_hciattach`, the RTL8723D will be fully functional for both HFP and A2DP profiles, solving the original disconnection issue.