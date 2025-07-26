# RV1106 RTL8723D Bluetooth HFP Solution

## Overview

This repository contains the complete solution for fixing Bluetooth HFP (Hands-Free Profile) disconnection issues on RV1106 SoC with RTL8723D Bluetooth chip.

**Problem**: HFP disconnects during phone calls with "Too small packet for stream_rej" error while A2DP works fine.

**Root Cause**: BlueALSA's HFP-HF (client) implementation is incomplete.

## Quick Start

### Immediate Workaround
```bash
# Use BlueALSA in HFP-AG (server) mode instead of HFP-HF
bluealsa -p hfp-ag -p a2dp-sink &
```

### Proper Solution
Build and install oFono for proper HFP support (see `codespaces_build_ofono_fixed.sh`)

## Repository Structure

```
├── PROJECT_STATUS.md           # Current project status and findings
├── SOLUTION_SUMMARY.md         # Comprehensive solution analysis
├── WEEKEND_PLAN.md            # Testing plans for Raspberry Pi
├── CONSOLIDATION_PLAN.md      # Repository consolidation guide
│
├── RV1106-BlueFusion-HFP/     # BlueFusion extension for Classic BT
├── tools/rtk_hciattach/       # Compiled Realtek initialization tool
├── scanner/                   # Bluetooth scanning utilities
├── scripts/                   # Various initialization scripts
│
├── codespaces_build_*.sh      # GitHub Codespaces build scripts
└── docs/                      # Additional documentation
```

## Key Findings

1. **Hardware**: RTL8723D responds at 1500000 baud (not 115200)
2. **Firmware**: Located at `/lib/firmware/rtlbt/`
3. **Issue**: H5 sync timeout prevents proper initialization
4. **Software**: BlueALSA HFP-HF is broken, need oFono or PipeWire

## Solutions

### 1. BlueALSA Workaround (Quick)
- Use HFP-AG mode instead of HFP-HF
- Device acts as "phone" not "headset"

### 2. oFono Integration (Proper)
- Build oFono using GitHub Codespaces
- Handles HFP properly while BlueALSA handles A2DP

### 3. PipeWire (Modern)
- Complete replacement for PulseAudio/BlueALSA
- Native HFP support

## Building for ARM (RV1106)

Using GitHub Codespaces:
```bash
# Clone repo
git clone https://github.com/ebowwa/RV1106-RTL8723D-HFP.git
cd RV1106-RTL8723D-HFP

# In Codespaces
chmod +x codespaces_build_ofono_fixed.sh
./codespaces_build_ofono_fixed.sh
```

## Weekend Plans

**Saturday**: Test on Raspberry Pi with native Linux
- Compare BlueALSA vs oFono vs PulseAudio
- Find optimal HFP configuration

**Sunday**: Fix HATs button integration
- GPIO control for Bluetooth functions
- Multi-press functionality

## Related Projects

This consolidates work from:
- [RTL8723D-Fix](https://github.com/ebowwa/RTL8723D-Fix) (archived)
- BlueFusion extensions for Classic Bluetooth

## Resources

- [Original Issue PDF](RV1106-BLE-HF-Bringup-Issue.pdf)
- [Project Status](PROJECT_STATUS.md)
- [Weekend Testing Plan](WEEKEND_PLAN.md)

## License

MIT