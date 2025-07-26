# BlueFusion Classic Bluetooth Extension

This extension adds Classic Bluetooth support to BlueFusion, complementing the existing BLE capabilities. It specifically addresses HFP (Hands-Free Profile) issues like those experienced with the RV1106 + RTL8723D setup.

## Features

### 1. Classic Bluetooth Adapter
- Device scanning and discovery
- Profile detection (HFP, HSP, A2DP, etc.)
- Connection management
- Both PyBluez and hcitool backends

### 2. HFP Protocol Handler
- Complete AT command tracking
- State machine monitoring
- Feature negotiation analysis
- Codec selection tracking
- Failure pattern recognition

### 3. SCO Audio Analyzer
- Audio quality metrics
- Packet loss detection
- Latency and jitter analysis
- Codec performance comparison
- Real-time quality scoring

### 4. RV1106 Device Adapter
- Direct USB control via rkdeveloptool
- RTL8723D initialization
- BlueALSA integration
- HFP connection testing
- Diagnostic log collection

## Usage

### Testing HFP on RV1106

1. Connect your RV1106 device via USB-C
2. Install rkdeveloptool:
   ```bash
   git clone https://github.com/rockchip-linux/rkdeveloptool
   cd rkdeveloptool
   autoreconf -i
   ./configure
   make
   sudo make install
   ```

3. Run the HFP test:
   ```bash
   python test_rv1106_hfp.py YOUR_PHONE_MAC_ADDRESS
   ```

### API Endpoints

The Classic Bluetooth API is available at `/api/classic/`:

- `GET /api/classic/status` - Get adapter status
- `GET /api/classic/devices` - Scan for devices
- `POST /api/classic/hfp/connect` - Connect HFP
- `GET /api/classic/hfp/{connection_id}/status` - Get connection status
- `GET /api/classic/hfp/{address}/analysis` - Analyze HFP failures

### WebSocket Monitoring

Connect to `/api/classic/ws/monitor` for real-time updates.

## Architecture

```
BlueFusion Extended
├── BLE (existing)
│   ├── MacBook BLE
│   └── Sniffer Dongle
└── Classic (new)
    ├── Classic Adapter
    ├── HFP Handler
    ├── SCO Analyzer
    └── RV1106 Adapter
```

## Troubleshooting HFP Issues

### Common Problems

1. **"Too small packet for stream_rej"**
   - Indicates codec negotiation failure
   - Try forcing CVSD codec only

2. **SCO disconnection during call**
   - Check SCO routing (HCI vs PCM)
   - Verify kernel SCO support

3. **Service Level Connection fails**
   - Ensure both devices support required features
   - Check AT command flow in analysis

### Solutions

1. **Use CVSD only**:
   ```bash
   bluealsa -p hfp-hf --hfp-codec=cvsd
   ```

2. **Configure SCO routing**:
   ```bash
   echo 1 > /sys/module/bluetooth/parameters/disable_esco
   hciconfig hci0 voice 0x0060
   ```

3. **Try oFono instead**:
   ```bash
   apt-get install ofono
   ofonod --plugin=hfp_hf_bluez5
   ```

## Requirements

- Python 3.8+
- PyBluez (optional, falls back to hcitool)
- rkdeveloptool (for RV1106 support)
- BlueALSA or oFono
- Linux with SCO support

## Contributing

To add support for more devices or profiles:

1. Create adapter in `src/classic/`
2. Implement profile handler
3. Add API endpoints
4. Update unified monitor

## License

Same as BlueFusion main project.