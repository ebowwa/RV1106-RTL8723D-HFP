#!/bin/bash
# Quick fix for RV1106 Bluetooth - One command solution

# Run this directly on your Mac/Linux host:
# curl -sL https://your-url/quick_fix.sh | bash

echo "🔧 RV1106 Bluetooth Quick Fix"
echo "============================"

# Check ADB
if ! command -v adb &> /dev/null; then
    echo "❌ ADB not found. Please install: brew install android-platform-tools"
    exit 1
fi

# Check device
if ! adb devices | grep -q device$; then
    echo "❌ No device connected. Please connect RV1106 via USB"
    exit 1
fi

echo "✅ Device connected"

# One-liner fix commands
adb shell << 'DEVICE_COMMANDS'
# Kill existing
killall hciattach bluealsa 2>/dev/null

# GPIO reset (adjust pins for your board)
echo 110 > /sys/class/gpio/export 2>/dev/null
echo out > /sys/class/gpio/gpio110/direction 2>/dev/null
echo 0 > /sys/class/gpio/gpio110/value 2>/dev/null
sleep 0.1
echo 1 > /sys/class/gpio/gpio110/value 2>/dev/null

# Try multiple baud rates
for BAUD in 1500000 921600 460800 230400 115200; do
    echo "Trying $BAUD baud..."
    hciattach /dev/ttyS5 any $BAUD flow noflow
    sleep 2
    
    if hciconfig hci0 2>/dev/null | grep -q "BD Address"; then
        echo "✅ Success at $BAUD baud!"
        
        # Configure HCI
        hciconfig hci0 up
        hciconfig hci0 piscan
        hciconfig hci0 sspmode 1
        hciconfig hci0 name "RV1106"
        
        # Force CVSD codec
        hciconfig hci0 voice 0x0060
        
        # Start BlueALSA
        bluealsa -p hfp-hf --hfp-codec=cvsd &
        
        echo "✅ Bluetooth initialized!"
        hciconfig -a
        exit 0
    fi
done

echo "❌ Failed to initialize Bluetooth"
exit 1
DEVICE_COMMANDS

# Check result
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Bluetooth is now working!"
    echo ""
    echo "Test commands:"
    echo "  adb shell hcitool scan     # Scan for devices"
    echo "  adb shell hciconfig -a     # Check status"
    echo ""
else
    echo ""
    echo "❌ Initialization failed. Try:"
    echo "  ./rv1106_bluetooth_manager.sh --fix"
fi