# RV1106 RTL8723D Bluetooth Project Status

## Project Overview
**Goal**: Fix HFP (Hands-Free Profile) disconnection issues on RV1106 SoC with RTL8723D Bluetooth chip

**Initial Problem** (from PDF):
- A2DP works fine (music streaming)
- HFP disconnects during phone calls with error: "Too small packet for stream_rej"
- Using BlueALSA which has limited HFP-HF support

## What We've Done

### 1. Problem Analysis ✅
- Identified root cause: BlueALSA's HFP-HF (client) implementation is incomplete
- The error "Too small packet for stream_rej" confirms protocol handling issue
- A2DP works because BlueALSA handles it well

### 2. Hardware Investigation ✅
- Connected to RV1106 via ADB over USB-C
- Discovered RTL8723D responds at **1500000 baud** (not 115200)
- Found firmware location: `/lib/firmware/rtlbt/`
- Identified UART: `/dev/ttyS5`
- Found existing binaries: `/userdata/rtkhci`

### 3. BlueFusion Extension ✅
Created Classic Bluetooth capabilities:
```
RV1106-BlueFusion-HFP/
├── src/
│   ├── classic_adapter.py    # Classic BT support
│   ├── hfp_handler.py       # HFP protocol analyzer
│   ├── sco_analyzer.py      # SCO audio analysis
│   └── at_debugger.py       # AT command debugger
```

### 4. Cross-Compilation (GitHub Codespaces) ✅
- Successfully compiled `rtk_hciattach` for ARM
- Created build scripts for macOS → ARM workflow
- Deployed to device via ADB

### 5. Initialization Attempts ❌
Multiple approaches tried:
- `rtkhci` - H5 sync timeout
- `rtk_hciattach` - H5 sync timeout  
- Standard `hciattach` at 1500000 - Partial success but no firmware load
- Result: HCI interface exists but BD Address stays 00:00:00:00:00:00

### 6. oFono Build (In Progress) 🔄
- Started building oFono in Codespaces for proper HFP support
- Hit GLib dependency issues
- Created fixed build script with ARM dependencies

## Current Issues

### 1. Bluetooth Initialization
- H5 sync timeout with both rtkhci and rtk_hciattach
- HCI interface won't come UP (Error 132)
- Firmware not loading properly

### 2. Software Stack
- BlueALSA's HFP-HF is broken (confirmed)
- Need oFono for proper HFP support
- No package manager on device

## Solutions

### Option 1: Fix BlueALSA (Quick Workaround)
```bash
# Use HFP-AG mode instead of HFP-HF
bluealsa -p hfp-ag -p a2dp-sink &
# Device acts as "phone" not "headset"
```

### Option 2: Build oFono (Proper Fix)
```bash
# In GitHub Codespaces
./codespaces_build_ofono_fixed.sh
# Deploy to device
./deploy_ofono_rv1106.sh
```

### Option 3: Use PipeWire (Modern Approach)
- Handles both A2DP and HFP properly
- Requires build system integration

## Next Steps

### Saturday - Raspberry Pi Testing
1. **Test on Raspberry Pi with Linux**
   - Native compilation (no cross-compile needed)
   - Better package management (apt)
   - Can install oFono directly: `sudo apt install ofono`
   - Test BlueALSA vs oFono vs PipeWire

2. **Bluetooth Stack Comparison**
   ```bash
   # Test 1: BlueALSA HFP-AG mode
   bluealsa -p hfp-ag -p a2dp-sink
   
   # Test 2: oFono + BlueALSA
   ofonod &  # Handles HFP
   bluealsa -p a2dp-sink &  # Handles A2DP only
   
   # Test 3: PipeWire
   pipewire &
   wireplumber &
   ```

3. **Document Working Configuration**
   - Which stack works best
   - Audio quality comparison
   - CPU usage
   - Latency measurements

### Sunday - HATs Button Fix
1. **GPIO Control**
   - Map button to Bluetooth functions
   - Toggle profiles (A2DP/HFP)
   - Reset Bluetooth stack

2. **Integration**
   - Connect button events to BlueFusion
   - Add status LEDs if available

## Repository Consolidation Needed

Currently have two repos:
1. `RV1106-RTL8723D-HFP` - Main project
2. `BlueFusion` fork - Should be integrated

**TODO**: Merge BlueFusion extensions into main repo

## Key Learnings

1. **Hardware**: RTL8723D needs specific initialization at 1500000 baud
2. **Software**: BlueALSA HFP-HF is fundamentally broken
3. **Solution**: Need oFono or PipeWire for proper HFP
4. **Development**: GitHub Codespaces works well for ARM cross-compilation

## Resources

- Original issue PDF: `/Users/ebowwa/Desktop/RV1106-BLE-HF-Bringup-Issue.pdf`
- GitHub repo: https://github.com/ebowwa/RV1106-RTL8723D-HFP
- Build scripts in: `codespaces_build_*.sh`
- Device access: ADB over USB-C

## Commands Reference

```bash
# Connect to device
adb shell

# Check Bluetooth
hciconfig -a
hcitool scan

# Initialize (what partially works)
hciattach /dev/ttyS5 any 1500000 flow

# Monitor HFP
dbus-monitor --system "type='signal',interface='org.ofono.Modem'"
```