# RV1106 Device Scanner

Universal device scanner for RV1106 that can detect:
- Serial/UART devices
- Bluetooth Classic devices
- Bluetooth Low Energy (BLE) devices

## Components

### 1. Python Scanner (`device_scanner.py`)
Comprehensive scanner with JSON output support.

```bash
# Scan everything
python3 device_scanner.py

# Scan only serial devices
python3 device_scanner.py serial

# Scan only Bluetooth Classic
python3 device_scanner.py classic

# Scan only BLE
python3 device_scanner.py ble
```

### 2. Shell Scanner (`device_scanner.sh`)
Lightweight shell script for quick scanning.

```bash
# Scan all devices
./device_scanner.sh

# Specific scans
./device_scanner.sh serial
./device_scanner.sh classic
./device_scanner.sh ble
./device_scanner.sh info
```

### 3. Real-time Scanner (`realtime_scanner.c`)
C program that continuously monitors devices.

```bash
# Compile for ARM
make arm

# Deploy to device
make deploy

# Run on device
adb shell "/tmp/realtime_scanner.arm"
```

## Deployment

1. Build for ARM (on Linux or GitHub Codespaces):
```bash
make arm
```

2. Deploy all scanners to RV1106:
```bash
make deploy
```

3. Run on device:
```bash
# Python scanner
adb shell "cd /tmp && python3 device_scanner.py"

# Shell scanner
adb shell "/tmp/device_scanner.sh"

# Real-time scanner
adb shell "/tmp/realtime_scanner.arm"
```

## Output

The Python scanner creates JSON files with results:
```json
{
  "scan_time": "2024-01-26T10:30:00",
  "serial_devices": [
    {
      "device": "/dev/ttyS5",
      "permissions": "crw-rw----",
      "owner": "root",
      "group": "dialout",
      "baud_rate": "115200"
    }
  ],
  "bluetooth_classic": [
    {
      "address": "AA:BB:CC:DD:EE:FF",
      "name": "Device Name",
      "type": "classic",
      "class": "0x240404"
    }
  ],
  "bluetooth_le": [
    {
      "address": "11:22:33:44:55:66",
      "name": "BLE Device",
      "type": "ble",
      "rssi": -65
    }
  ]
}
```

## Troubleshooting

### Bluetooth not initialized
The scanners will try to initialize Bluetooth automatically using:
1. `/tmp/rtk_hciattach` (if available)
2. `/userdata/rtkhci` (if available)
3. Standard `hciattach` at 1500000 baud

### No devices found
- Check if Bluetooth service is running
- Verify serial port permissions
- Ensure hardware is properly connected

### Build errors
For ARM compilation, ensure you have:
```bash
sudo apt-get install gcc-arm-linux-gnueabihf libbluetooth-dev
```