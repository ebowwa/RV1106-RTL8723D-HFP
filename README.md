# RV1106 + RTL8723D Bluetooth HFP Solution

This repository contains a comprehensive solution for fixing HFP (Hands-Free Profile) disconnection issues on RV1106 devices with RTL8723D Bluetooth chips.

## 🎯 Problem Statement

The RV1106 + RTL8723D hardware combination experiences disconnections during HFP phone calls while A2DP music streaming works correctly. This project provides analysis, debugging tools, and solutions.

## 📁 Repository Structure

```
RV1106-RTL8723D-Project/
├── bluez-alsa/          # BlueALSA source analysis
│   └── src/             # HFP implementation files
├── ofono/               # oFono HFP reference implementation  
│   └── plugins/         # HFP plugin source
├── BlueFusion/          # BLE-focused framework (extended)
│   └── src/             # Core BlueFusion modules
├── RV1106-BlueFusion-HFP/  # Main solution
│   ├── src/             # Python implementation
│   ├── scripts/         # Deployment & test scripts
│   ├── device_code/     # C code for device
│   └── docs/            # Documentation
└── tools/               # Build tools & utilities
    └── rtk_hciattach/   # RTL8723D initialization
```

## 🔧 Key Findings

1. **Root Cause**: RTL8723D requires specific initialization with `rtk_hciattach`
2. **Baud Rate**: Device operates at 1500000 baud (not standard 115200)
3. **Firmware**: Located at `/lib/firmware/rtlbt/` on device
4. **Solution**: Proper firmware loading enables full HFP functionality

## 🚀 Quick Start

### Prerequisites
- RV1106 device with RTL8723D Bluetooth chip
- ADB access to device
- ARM cross-compiler (for building rtk_hciattach)

### Build rtk_hciattach

Using GitHub Codespaces (recommended for macOS users):

```bash
# Create codespace from this repo
# In codespace terminal:
cd tools/rtk_hciattach
./build.sh
```

### Deploy Solution

```bash
# Push rtk_hciattach to device
adb push tools/rtk_hciattach/rtk_hciattach /tmp/
adb shell "chmod +x /tmp/rtk_hciattach"

# Initialize RTL8723D
adb shell "/tmp/rtk_hciattach -n -s 115200 /dev/ttyS5 rtk_h5"

# Verify initialization
adb shell "hciconfig -a"

# Deploy BlueFusion HFP solution
cd RV1106-BlueFusion-HFP
./deploy.sh
```

## 📊 Components

### 1. BlueALSA Analysis
- Limited HFP-HF (client) implementation
- SCO audio routing issues identified
- Source code analysis in `bluez-alsa/src/`

### 2. oFono Reference
- Complete HFP implementation with telephony stack
- Better state machine for call handling
- Reference code in `ofono/plugins/`

### 3. BlueFusion Extension
- Added Classic Bluetooth support
- HFP protocol analyzer
- SCO audio quality metrics
- Python implementation for rapid development

### 4. RV1106 Device Integration
- Hardware-specific initialization scripts
- ADB-based deployment
- Real-time debugging tools

## 🛠️ Building from Source

### On Linux:
```bash
# Install ARM toolchain
sudo apt-get install gcc-arm-linux-gnueabihf

# Build rtk_hciattach
cd tools/rtk_hciattach
make
```

### On macOS:
Use GitHub Codespaces or Docker:
```bash
# Using Docker
docker run --rm -v $PWD:/src arm32v7/gcc:9 make
```

## 📝 Documentation

- [HFP Disconnection Analysis](RV1106-BlueFusion-HFP/docs/HFP_ANALYSIS.md)
- [RTL8723D Initialization](RV1106-BlueFusion-HFP/docs/RTL8723D_INIT.md)
- [BlueFusion API Reference](BlueFusion/docs/API.md)
- [Deployment Guide](RV1106-BlueFusion-HFP/docs/DEPLOYMENT.md)

## 🐛 Debugging

Enable verbose logging:
```bash
adb shell "hcidump -X -t"  # HCI packet dump
adb shell "logcat | grep -i bluetooth"  # System logs
```

Run diagnostics:
```python
cd RV1106-BlueFusion-HFP
python3 src/test_runner.py --device-ip <IP>
```

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/improvement`)
3. Commit changes (`git commit -m 'Add feature'`)
4. Push branch (`git push origin feature/improvement`)
5. Open Pull Request

## 📄 License

This project is licensed under the MIT License - see LICENSE file for details.

## 🙏 Acknowledgments

- BlueALSA project for Bluetooth audio implementation
- oFono project for HFP reference
- Realtek for RTL8723D documentation
- Rockchip for RV1106 platform support