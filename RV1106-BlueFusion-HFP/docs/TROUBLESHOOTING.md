# BlueFusion Classic Bluetooth Quick Reference

## RV1106 HFP Testing - Quick Commands

### 1. Quick Setup (One-time)
```bash
# Install dependencies
sudo apt-get install -y bluetooth bluez bluez-tools
pip install pybluez pyaudio

# Install rkdeveloptool
git clone https://github.com/rockchip-linux/rkdeveloptool.git
cd rkdeveloptool && autoreconf -i && ./configure && make && sudo make install
```

### 2. Test HFP Connection
```bash
# Basic test (replace XX:XX:XX:XX:XX:XX with phone MAC)
python test_rv1106_hfp.py XX:XX:XX:XX:XX:XX

# Monitor mode
python test_rv1106_hfp.py --monitor

# With custom rkdeveloptool path
python test_rv1106_hfp.py --rkdeveloptool /path/to/rkdeveloptool XX:XX:XX:XX:XX:XX
```

### 3. Common Fixes

#### Force CVSD Codec Only
```bash
bluealsa -p a2dp-sink -p hfp-hf --hfp-codec=cvsd &
```

#### Fix SCO Routing
```bash
echo 1 > /sys/module/bluetooth/parameters/disable_esco
hciconfig hci0 voice 0x0060
```

#### Reset Bluetooth
```bash
sudo systemctl restart bluetooth
sudo hciconfig hci0 reset
```

### 4. Diagnostic Commands
```bash
# Check device connection
sudo rkdeveloptool ld

# Monitor Bluetooth traffic
btmon

# Check HFP status
bluetoothctl info XX:XX:XX:XX:XX:XX

# View logs
dmesg | grep -i bluetooth | tail -20
```

### 5. API Quick Test
```bash
# Start server
python -m src.api.fastapi_server

# Test endpoints
curl http://localhost:8000/api/classic/status
curl http://localhost:8000/api/classic/devices
```

## Test Output Interpretation

### Success Indicators
- ✅ "HFP CONNECTION SUCCESSFUL!"
- ✅ "SCO connected"
- ✅ "Service level connection established"

### Failure Indicators
- ❌ "Too small packet for stream_rej"
- ❌ "SCO connection failed"
- ❌ "Codec negotiation incomplete"

## Quick Troubleshooting

| Problem | Quick Fix |
|---------|-----------|
| No device found | Check USB connection, run `lsusb` |
| HFP drops on call | Use CVSD codec only |
| No audio | Check SCO routing settings |
| Connection timeout | Remove old pairing, retry |
| Codec negotiation fails | Disable mSBC, use CVSD |

## Emergency Reset
```bash
# Kill all Bluetooth processes
sudo killall bluetoothd bluealsa bluealsa-aplay

# Reset hardware
sudo hciconfig hci0 reset

# Restart from scratch
sudo systemctl restart bluetooth
```