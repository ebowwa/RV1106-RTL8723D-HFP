# RV1106 BlueFusion HFP Solution

A complete Classic Bluetooth HFP (Hands-Free Profile) solution for RV1106 devices with RTL8723D, built on top of BlueFusion.

## Overview

This project solves the HFP disconnection issue described in the RV1106-BLE-HF-Bringup-Issue PDF by providing:
- Comprehensive HFP protocol analysis
- SCO audio quality monitoring
- Direct USB device control via rkdeveloptool
- Real-time diagnostics and troubleshooting

## Quick Start

```bash
# 1. Run the setup script
./setup.sh

# 2. Test HFP connection
python rv1106_hfp_test.py YOUR_PHONE_MAC_ADDRESS

# 3. Monitor mode
python rv1106_hfp_test.py --monitor
```

## Project Structure

```
RV1106-BlueFusion-HFP/
├── README.md                   # This file
├── setup.sh                    # One-click setup script
├── requirements.txt            # Python dependencies
├── rv1106_hfp_test.py         # Main test script
├── src/
│   ├── classic_adapter.py     # Classic Bluetooth core
│   ├── hfp_handler.py         # HFP protocol implementation
│   ├── sco_audio.py           # SCO audio analyzer
│   ├── rv1106_adapter.py      # RV1106 device control
│   └── unified_monitor.py     # Combined monitoring
├── api/
│   ├── server.py              # FastAPI server
│   └── classic_routes.py      # REST endpoints
├── docs/
│   ├── SETUP_GUIDE.md         # Detailed setup instructions
│   ├── TROUBLESHOOTING.md     # Common issues and fixes
│   └── API_REFERENCE.md       # API documentation
└── config/
    └── default.yaml           # Default configuration
```

## Key Features

1. **HFP Connection Analysis**
   - AT command tracking
   - State machine monitoring
   - Codec negotiation analysis
   - Failure pattern recognition

2. **Audio Quality Monitoring**
   - Real-time packet loss detection
   - Latency and jitter measurement
   - Quality score calculation
   - Codec performance comparison

3. **Device Control**
   - Direct USB communication
   - Automated Bluetooth initialization
   - Log collection and analysis
   - SCO routing configuration

4. **API and Monitoring**
   - REST API for remote control
   - WebSocket for real-time updates
   - Web dashboard (optional)
   - Continuous monitoring mode

## Requirements

- Linux system (Ubuntu 20.04+)
- Python 3.8+
- RV1106 device with RTL8723D
- USB-C connection
- Phone with Bluetooth for testing

## Documentation

- [Setup Guide](docs/SETUP_GUIDE.md) - Complete installation instructions
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [API Reference](docs/API_REFERENCE.md) - REST API documentation

## License

MIT License - See LICENSE file for details.