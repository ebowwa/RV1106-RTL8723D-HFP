#!/bin/bash
# Use our compiled rtk_hciattach

cat > /tmp/use_rtk_hciattach.sh << 'EOF'
#!/bin/sh
# Use our compiled rtk_hciattach

echo "=== Using our rtk_hciattach ==="

# Clean up
killall -q rtkhci rtk_hciattach hciattach bluealsa bluetoothd 2>/dev/null
sleep 2

# Check if our rtk_hciattach exists
if [ ! -f /tmp/rtk_hciattach ]; then
    echo "ERROR: /tmp/rtk_hciattach not found!"
    exit 1
fi

echo "Found rtk_hciattach, making it executable..."
chmod +x /tmp/rtk_hciattach

# Try initialization
echo -e "\nInitializing with rtk_hciattach..."
/tmp/rtk_hciattach -s 115200 /dev/ttyS5 rtk_h5 &
RTK_PID=$!

echo "Started rtk_hciattach with PID: $RTK_PID"
echo "Waiting for initialization (this loads firmware)..."

# Monitor output
sleep 15

# Check if still running
if kill -0 $RTK_PID 2>/dev/null; then
    echo "rtk_hciattach is still running (good sign)"
else
    echo "rtk_hciattach exited"
fi

# Check HCI interface
echo -e "\nChecking HCI interface:"
hciconfig -a

# Try to bring up
echo -e "\nTrying to bring up interface:"
hciconfig hci0 down 2>/dev/null
sleep 1
hciconfig hci0 up 2>/dev/null

# Final check
echo -e "\nFinal status:"
hciconfig hci0

# Check dmesg for any kernel messages
echo -e "\nKernel messages:"
dmesg | tail -20 | grep -E "(Bluetooth|hci|rtk|RTL)" || echo "No relevant kernel messages"

EOF

adb push /tmp/use_rtk_hciattach.sh /tmp/
adb shell "chmod +x /tmp/use_rtk_hciattach.sh && /tmp/use_rtk_hciattach.sh"