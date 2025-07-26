#!/bin/bash
# Deploy BlueFusion HFP solution to RV1106

echo "🚀 Deploying RV1106-BlueFusion-HFP Solution"
echo "==========================================="

# Check ADB connection
if ! adb devices | grep -q "device$"; then
    echo "❌ No ADB device connected"
    exit 1
fi

echo "✓ Device connected"

# Create directories on device
echo "Creating directories..."
adb shell "mkdir -p /data/bluefusion/{src,scripts,logs}"

# Push Python modules
echo "Deploying Python modules..."
for file in src/*.py; do
    if [ -f "$file" ]; then
        adb push "$file" /data/bluefusion/src/
    fi
done

# Push scripts
echo "Deploying scripts..."
for file in scripts/*.sh; do
    if [ -f "$file" ]; then
        adb push "$file" /data/bluefusion/scripts/
        adb shell "chmod +x /data/bluefusion/scripts/$(basename $file)"
    fi
done

# Push device code if compiled
if [ -f "device_code/rtk_hciattach" ]; then
    echo "Deploying rtk_hciattach..."
    adb push device_code/rtk_hciattach /tmp/
    adb shell "chmod +x /tmp/rtk_hciattach"
fi

# Create startup script
cat > /tmp/start_bluefusion.sh << 'EOF'
#!/bin/sh
echo "Starting BlueFusion HFP Solution..."

# Initialize Bluetooth if rtk_hciattach available
if [ -f /tmp/rtk_hciattach ]; then
    echo "Initializing RTL8723D..."
    killall hciattach 2>/dev/null
    /tmp/rtk_hciattach -n -s 115200 /dev/ttyS5 rtk_h5 &
    sleep 5
else
    echo "Using fallback initialization..."
    hciattach /dev/ttyS5 any 1500000 flow noflow &
    sleep 3
fi

# Verify Bluetooth
hciconfig hci0 up
hciconfig -a

# Start BlueALSA
bluealsa -p hfp-hf -p a2dp-sink &

# Start BlueFusion monitor
cd /data/bluefusion
python3 src/main.py --monitor &

echo "✓ BlueFusion HFP started"
EOF

# Deploy startup script
adb push /tmp/start_bluefusion.sh /data/bluefusion/
adb shell "chmod +x /data/bluefusion/start_bluefusion.sh"

# Run deployment test
echo -e "\n📋 Running deployment test..."
adb shell "/data/bluefusion/start_bluefusion.sh"

echo -e "\n✅ Deployment complete!"
echo "To start manually: adb shell '/data/bluefusion/start_bluefusion.sh'"
echo "Logs available at: /data/bluefusion/logs/"