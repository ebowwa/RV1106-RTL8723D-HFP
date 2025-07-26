# Using GitHub Codespace to Build rtk_hciattach

## Quick Steps:

### 1. Create a GitHub Repository
```bash
cd /Users/ebowwa/bluez-alsa/BlueFusion/RV1106-BlueFusion-HFP
gh repo create RV1106-RTL8723D-Fix --public --source=. --remote=origin --push
```

### 2. Open in Browser
Go to: https://github.com/YOUR_USERNAME/RV1106-RTL8723D-Fix

### 3. Create Codespace
- Click the green "Code" button
- Select "Codespaces" tab
- Click "Create codespace on main"

### 4. In Codespace Terminal
```bash
# Install ARM toolchain
sudo apt-get update
sudo apt-get install -y gcc-arm-linux-gnueabihf

# Clone rtk_hciattach
git clone https://github.com/seuscq/rtk_hciattach.git
cd rtk_hciattach

# Build for ARM
arm-linux-gnueabihf-gcc -static -o rtk_hciattach hciattach.c hciattach_rtk.c

# Verify
file rtk_hciattach
ls -la rtk_hciattach
```

### 5. Download Binary
- In Codespace: Right-click on `rtk_hciattach` file
- Select "Download"

### 6. Deploy to Device
```bash
# On your Mac
adb push ~/Downloads/rtk_hciattach /tmp/
adb shell "chmod +x /tmp/rtk_hciattach"
adb shell "/tmp/rtk_hciattach -n -s 115200 /dev/ttyS5 rtk_h5"
```

## Alternative: Use Gitpod
1. Go to: https://gitpod.io/#https://github.com/seuscq/rtk_hciattach
2. It will automatically open a Linux environment
3. Run the build commands above

This is the easiest way to compile ARM binaries on macOS\!
EOF < /dev/null