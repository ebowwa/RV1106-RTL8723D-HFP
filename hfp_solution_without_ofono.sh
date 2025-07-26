#!/bin/bash
# HFP solution without oFono - using BlueALSA in AG mode

cat > /tmp/hfp_solution.sh << 'EOF'
#!/bin/sh
# HFP Solution using BlueALSA in AG (Audio Gateway) mode

echo "=== HFP Solution Without oFono ==="
echo "Using BlueALSA in HFP-AG mode (server) instead of HFP-HF (client)"

# The key insight from the PDF:
# - BlueALSA HFP-HF (client) mode is broken
# - BlueALSA HFP-AG (server) mode works better
# - This means the RV1106 acts as the "phone" side

# 1. Clean start
echo "1. Cleaning up..."
killall -q bluealsa bluetoothd hciattach 2>/dev/null
sleep 2

# 2. Initialize Bluetooth (using working method)
echo "2. Initializing Bluetooth..."
hciattach /dev/ttyS5 any 1500000 flow &
sleep 5

# 3. Configure HCI
echo "3. Configuring HCI..."
hciconfig hci0 up 2>/dev/null
hciconfig hci0 piscan
hciconfig hci0 class 0x40020C  # Phone device class (for AG mode)
hciconfig hci0 sspmode 1

# 4. Start D-Bus
echo "4. Starting D-Bus..."
if [ ! -f /run/dbus/pid ]; then
    dbus-daemon --system &
    sleep 2
fi

# 5. Start BlueZ
echo "5. Starting BlueZ..."
bluetoothd --experimental -n -d &
sleep 3

# 6. Start BlueALSA with HFP-AG mode
echo "6. Starting BlueALSA in HFP-AG mode..."
# HFP-AG works better than HFP-HF in BlueALSA
bluealsa -p a2dp-sink -p a2dp-source -p hfp-ag --hfp-msc &
BLUEALSA_PID=$!
sleep 2

# 7. Configure SCO routing
echo "7. Configuring SCO audio routing..."
# SCO routing options:
# - HCI: Route SCO over HCI (software)
# - PCM: Route SCO over PCM/I2S (hardware)
hcitool cmd 0x3f 0x001c 0x01 0x00 0x00 0x00  # Enable SCO over HCI

# 8. Start audio
bluealsa-aplay 00:00:00:00:00:00 &

echo -e "\n=== HFP-AG Mode Setup Complete ==="
echo ""
echo "IMPORTANT: This setup uses HFP-AG (Audio Gateway) mode"
echo "This means:"
echo "- RV1106 acts as the 'phone' side (AG)"
echo "- Your phone connects as 'headset' (HF)"
echo "- This is opposite of normal, but works around BlueALSA's HFP-HF bug"
echo ""
echo "To use:"
echo "1. In bluetoothctl:"
echo "   power on"
echo "   agent on"
echo "   default-agent"
echo "   discoverable on"
echo "   pairable on"
echo ""
echo "2. On your phone:"
echo "   - Look for 'RV1106-BT' and pair"
echo "   - It will appear as a 'headset' device"
echo "   - Audio routing may be reversed"
echo ""
echo "Alternative: Use our BlueFusion HFP implementation"

# Show status
echo -e "\n=== Status ==="
hciconfig hci0
ps | grep -E "(bluealsa|bluetoothd)" | grep -v grep

# Create SCO test script
cat > /tmp/test_sco.sh << 'SCO_EOF'
#!/bin/sh
# Test SCO audio connection

echo "=== Testing SCO Audio ==="

# Check SCO parameters
echo "SCO MTU and packet types:"
hciconfig hci0 revision

# Monitor SCO connections
echo -e "\nMonitoring for SCO connections..."
echo "Make a call to test..."
hcitool con
SCO_EOF

chmod +x /tmp/test_sco.sh
echo -e "\nCreated SCO test script: /tmp/test_sco.sh"

EOF

# Deploy and run
adb push /tmp/hfp_solution.sh /tmp/
adb shell "chmod +x /tmp/hfp_solution.sh && /tmp/hfp_solution.sh"