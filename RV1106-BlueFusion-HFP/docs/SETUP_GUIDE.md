# BlueFusion Classic Bluetooth Setup Guide

## Complete Setup for RV1106 + RTL8723D HFP Support

This guide documents the complete setup process for adding Classic Bluetooth support to BlueFusion, specifically targeting the RV1106 + RTL8723D hardware combination for HFP (Hands-Free Profile) functionality.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Hardware Setup](#hardware-setup)
3. [Software Installation](#software-installation)
4. [BlueFusion Classic Bluetooth Integration](#bluefusion-classic-bluetooth-integration)
5. [Testing and Diagnostics](#testing-and-diagnostics)
6. [Troubleshooting](#troubleshooting)
7. [API Reference](#api-reference)

## Prerequisites

### System Requirements
- Linux system (Ubuntu 20.04+ or similar)
- Python 3.8 or higher
- USB-C connection to RV1106 device
- Git and build tools

### Required Software
```bash
# Install system dependencies
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    git \
    python3-pip \
    python3-dev \
    libbluetooth-dev \
    bluetooth \
    bluez \
    bluez-tools \
    libasound2-dev \
    libdbus-1-dev \
    libglib2.0-dev \
    libsbc-dev \
    libusb-1.0-0-dev
```

## Hardware Setup

### 1. RV1106 + RTL8723D Connection

Connect your RV1106 device to your computer via USB-C. The device should appear as a Rockchip device.

```bash
# Check USB connection
lsusb | grep 2207
# Should show: Bus xxx Device xxx: ID 2207:110a Fuzhou Rockchip Electronics Company
```

### 2. Install rkdeveloptool

```bash
# Clone and build rkdeveloptool
git clone https://github.com/rockchip-linux/rkdeveloptool.git
cd rkdeveloptool
autoreconf -i
./configure
make
sudo make install

# Verify installation
rkdeveloptool -v
```

### 3. Verify Device Detection

```bash
# List connected Rockchip devices
sudo rkdeveloptool ld
# Output: DevNo=1	Vid=0x2207,Pid=0x110a,LocationID=101	Maskrom
```

## Software Installation

### 1. Install BlueALSA (with HFP support)

```bash
# Clone BlueALSA
git clone https://github.com/Arkq/bluez-alsa.git
cd bluez-alsa

# Configure with HFP support
autoreconf -fi
./configure --enable-hfp --enable-msbc --enable-debug

# Build and install
make
sudo make install

# Create systemd service
sudo cp misc/systemd/bluealsa.service /etc/systemd/system/
sudo systemctl daemon-reload
```

### 2. Install Python Dependencies

```bash
# Install BlueFusion dependencies
cd /path/to/BlueFusion
pip install -r requirements.txt

# Install additional Classic Bluetooth dependencies
pip install pybluez pyaudio

# On macOS, you might need:
pip install git+https://github.com/pybluez/pybluez.git
```

## BlueFusion Classic Bluetooth Integration

### 1. File Structure

The Classic Bluetooth extension adds the following files to BlueFusion:

```
BlueFusion/
├── src/
│   ├── classic/                    # Classic Bluetooth module
│   │   ├── __init__.py
│   │   ├── classic_adapter.py      # Core Classic BT functionality
│   │   ├── hfp_handler.py         # HFP protocol implementation
│   │   ├── sco_audio.py           # SCO audio analysis
│   │   ├── rv1106_adapter.py      # RV1106-specific control
│   │   └── README.md
│   ├── interfaces/
│   │   └── classic_base.py        # Classic BT interfaces
│   ├── api/
│   │   └── classic_routes.py      # REST API endpoints
│   └── unified_monitor.py         # Combined BLE/Classic monitoring
├── test_rv1106_hfp.py            # RV1106 HFP test script
└── CLASSIC_BLUETOOTH_SETUP.md     # This document
```

### 2. Key Components

#### Classic Bluetooth Adapter (`classic_adapter.py`)
- Device scanning and discovery
- HFP/HSP profile connection management
- SCO audio connection handling
- PyBluez and hcitool backends

#### HFP Protocol Handler (`hfp_handler.py`)
- AT command parsing and tracking
- HFP state machine implementation
- Feature negotiation monitoring
- Failure pattern analysis

#### SCO Audio Analyzer (`sco_audio.py`)
- Real-time audio quality metrics
- Packet loss detection
- Latency and jitter measurement
- Codec performance analysis

#### RV1106 Adapter (`rv1106_adapter.py`)
- Direct USB control via rkdeveloptool
- RTL8723D initialization automation
- BlueALSA integration
- Diagnostic log collection

### 3. API Integration

The Classic Bluetooth API extends BlueFusion's FastAPI server:

```python
# In your main FastAPI app
from src.api.classic_routes import router as classic_router
from src.api.classic_routes import initialize_classic_bluetooth

app = FastAPI()
app.include_router(classic_router)

@app.on_event("startup")
async def startup_event():
    await initialize_classic_bluetooth()
```

## Testing and Diagnostics

### 1. Basic HFP Test

```bash
# Test HFP connection to a phone
python test_rv1106_hfp.py E8:D5:2B:13:B5:AB

# Replace E8:D5:2B:13:B5:AB with your phone's Bluetooth MAC address
```

### 2. Continuous Monitoring

```bash
# Monitor HFP connections in real-time
python test_rv1106_hfp.py --monitor
```

### 3. API Testing

```bash
# Start BlueFusion server
python -m src.api.fastapi_server

# In another terminal, test Classic BT endpoints
curl http://localhost:8000/api/classic/status
curl http://localhost:8000/api/classic/devices?duration=10
```

### 4. WebSocket Monitoring

```javascript
// Connect to WebSocket for real-time updates
const ws = new WebSocket('ws://localhost:8000/api/classic/ws/monitor');
ws.onmessage = (event) => {
    const data = JSON.parse(event.data);
    console.log('Classic BT Status:', data);
};
```

## Troubleshooting

### Common Issues and Solutions

#### 1. HFP Connection Drops During Calls

**Symptom**: Connection establishes but drops when making/receiving calls

**Solutions**:
```bash
# Force CVSD codec only
bluealsa -p a2dp-sink -p hfp-hf --hfp-codec=cvsd &

# Configure SCO routing
echo 1 > /sys/module/bluetooth/parameters/disable_esco
hciconfig hci0 voice 0x0060
```

#### 2. "Too small packet for stream_rej" Error

**Symptom**: Error in btmon logs during HFP setup

**Solutions**:
```bash
# Start bluetoothd with experimental features
sudo /usr/libexec/bluetooth/bluetoothd --experimental --compat -n -d &

# Add HF SDP record manually
sdptool add HF
```

#### 3. No SCO Audio

**Symptom**: HFP connects but no audio during calls

**Solutions**:
```bash
# Check SCO MTU settings
hciconfig hci0 scomtu 64:8

# Try different packet types
hcitool cmd 0x01 0x0028 0x00 0x00 0x00 0x00 0x03 0x00 0x00 0x00
```

### Diagnostic Commands

```bash
# Check Bluetooth status
hciconfig -a
bluetoothctl show

# Monitor HCI traffic
btmon

# Check BlueALSA status
bluealsa-cli list-devices
bluealsa-cli list-pcms

# View kernel Bluetooth logs
dmesg | grep -i bluetooth
```

## API Reference

### Classic Bluetooth Endpoints

#### GET /api/classic/status
Get Classic Bluetooth adapter status

#### GET /api/classic/devices
Scan for Classic Bluetooth devices
- Query params: `duration` (default: 10 seconds)

#### POST /api/classic/hfp/connect
Connect to HFP device
- Body: `{"address": "XX:XX:XX:XX:XX:XX", "role": "HF"}`

#### GET /api/classic/hfp/{connection_id}/status
Get HFP connection status

#### POST /api/classic/hfp/{connection_id}/sco
Establish SCO audio connection

#### GET /api/classic/hfp/{address}/analysis
Analyze HFP connection failures

#### POST /api/classic/test/hfp/{address}
Run complete HFP connection test

### WebSocket Endpoints

#### WS /api/classic/ws/monitor
Real-time Classic Bluetooth monitoring

## Advanced Configuration

### 1. Custom HFP Features

Edit `src/classic/hfp_handler.py` to modify supported features:

```python
# Enable/disable specific HFP features
HF_FEATURES = {
    'codec_negotiation': True,    # mSBC support
    'wideband_speech': True,       # 16kHz audio
    'voice_recognition': False,    # Voice commands
    'volume_control': True,        # Remote volume
}
```

### 2. SCO Routing Options

```python
# In rv1106_adapter.py
async def configure_sco_routing(self, routing: str = "hci"):
    if routing == "hci":
        # Route SCO over USB (default)
        pass
    elif routing == "pcm":
        # Route SCO to hardware codec
        pass
```

### 3. Codec Priority

```python
# Set codec preference order
CODEC_PRIORITY = ["mSBC", "CVSD"]  # Try mSBC first, fall back to CVSD
```

## Performance Tuning

### 1. Reduce Latency

```bash
# Set real-time priority for Bluetooth
sudo chrt -f 50 bluealsa

# Adjust buffer sizes
bluealsa --a2dp-volume --sbc-quality=high --io-thread-rt-priority=50
```

### 2. Improve Audio Quality

```bash
# Use higher quality SBC settings for A2DP
bluealsa --sbc-quality=xq --sbc-bitpool=53
```

### 3. Optimize for Power

```bash
# Reduce sniff interval for better battery life
hcitool cmd 0x02 0x0003 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00
```

## Contributing

To extend BlueFusion's Classic Bluetooth support:

1. Add new profile handlers in `src/classic/`
2. Implement profile-specific interfaces
3. Add corresponding API endpoints
4. Update the unified monitor
5. Add tests and documentation

## License

Same as the main BlueFusion project.

## Support

For issues specific to Classic Bluetooth:
1. Check the troubleshooting section
2. Enable debug logging: `export BLUEALSA_DEBUG=1`
3. Collect logs: `btmon > btmon.log 2>&1`
4. Open an issue with logs attached