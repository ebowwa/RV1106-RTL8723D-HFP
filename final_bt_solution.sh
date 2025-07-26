#!/bin/bash
# Final solution based on PDF analysis

cat > /tmp/final_bt_solution.sh << 'EOF'
#!/bin/sh
# Complete Bluetooth solution combining all findings

echo "=== Final RTL8723D Bluetooth Solution ==="
echo "Based on PDF: A2DP works, HFP has issues"

# 1. Complete cleanup and reset
echo "1. Complete cleanup..."
killall -9 rtkhci rtk_hciattach hciattach btattach bluealsa bluetoothd dbus-daemon 2>/dev/null
sleep 3

# Reset UART completely
stty -F /dev/ttyS5 0 2>/dev/null
sleep 1

# 2. GPIO reset (from our findings)
echo "2. GPIO reset..."
for gpio in 139 140 141 142; do
    if [ -d /sys/class/gpio/gpio$gpio ]; then
        echo 0 > /sys/class/gpio/gpio$gpio/value 2>/dev/null
        sleep 0.2
        echo 1 > /sys/class/gpio/gpio$gpio/value 2>/dev/null
    fi
done
sleep 2

# 3. Start dbus (required)
echo "3. Starting dbus..."
if [ ! -f /run/dbus/pid ]; then
    dbus-daemon --system &
    sleep 2
fi

# 4. The key: use standard hciattach at 1500000 baud
echo "4. Initializing Bluetooth at 1500000 baud..."
echo "This is what actually responds on this hardware"
hciattach -s 1500000 /dev/ttyS5 any 1500000 flow &
HCI_PID=$!
sleep 8

# 5. Load firmware manually if needed
echo "5. Checking if firmware loaded..."
if hciconfig hci0 2>/dev/null | grep -q "BD Address: 00:00:00:00:00:00"; then
    echo "Firmware not loaded, trying manual load..."
    # Kill current attach
    kill $HCI_PID 2>/dev/null
    sleep 2
    
    # Try with rtk_hciattach once to load firmware
    if [ -f /tmp/rtk_hciattach ]; then
        echo "Using rtk_hciattach for firmware load..."
        /tmp/rtk_hciattach -s 1500000 /dev/ttyS5 rtk_h5 &
        sleep 10
        # Don't kill it, let it run
    elif [ -f /userdata/rtkhci ]; then
        echo "Using rtkhci for firmware load..."
        cd /userdata
        ./rtkhci -s 1500000 /dev/ttyS5 rtk_h5 &
        sleep 10
    fi
fi

# 6. Configure interface
echo -e "\n6. Configuring interface..."
hciconfig hci0 up 2>/dev/null || echo "Note: Interface may need manual bring up"
hciconfig hci0 piscan 2>/dev/null
hciconfig hci0 name 'RV1106-BT' 2>/dev/null
hciconfig hci0 class 0x240404 2>/dev/null
hciconfig hci0 sspmode 1 2>/dev/null

# 7. Start BlueZ with experimental
echo -e "\n7. Starting BlueZ..."
if [ -f /usr/libexec/bluetooth/bluetoothd ]; then
    bluetoothd --experimental -n &
    sleep 3
fi

# 8. Start BlueALSA (A2DP works per PDF)
echo -e "\n8. Starting BlueALSA for A2DP..."
bluealsa -p a2dp-source -p a2dp-sink &
sleep 2

bluealsa-aplay 00:00:00:00:00:00 &

echo -e "\n=== STATUS ==="
hciconfig -a
echo -e "\nProcesses:"
ps | grep -E "(hci|blue|rtk)" | grep -v grep

echo -e "\n=== SUMMARY ==="
echo "From the PDF analysis:"
echo "- A2DP (music streaming) works with this setup"
echo "- HFP (phone calls) disconnects with 'Too small packet for stream_rej'"
echo "- This suggests BlueALSA's HFP-HF implementation issue"
echo ""
echo "Solutions for HFP:"
echo "1. Use oFono instead of BlueALSA for HFP"
echo "2. Use HFP-AG (server) mode instead of HFP-HF (client)"
echo "3. Implement proper HFP handling in BlueFusion"

# Test if we can scan
echo -e "\n=== Testing Bluetooth scan ==="
timeout 10 hcitool scan || echo "Scan timeout"

EOF

adb push /tmp/final_bt_solution.sh /tmp/
adb shell "chmod +x /tmp/final_bt_solution.sh && /tmp/final_bt_solution.sh"