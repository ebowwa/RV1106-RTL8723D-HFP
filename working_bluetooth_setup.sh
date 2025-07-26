#!/bin/bash
# Working Bluetooth setup using hciattach at 1500000 baud

cat > /tmp/working_bt_setup.sh << 'EOF'
#!/bin/sh
# Complete working Bluetooth setup

echo "=== Working Bluetooth Setup ==="
echo "Using hciattach at 1500000 baud (proven to work)"

# 1. Clean start
echo "1. Cleaning up..."
killall -q dbus-daemon bluetoothd rtkhci rtk_hciattach hciattach bluealsa bluealsa-aplay 2>/dev/null
rm -f /run/messagebus.pid
sleep 2

# 2. Start dbus-daemon
echo "2. Starting dbus-daemon..."
dbus-daemon --system --print-pid --print-address &
sleep 1

# 3. Initialize with hciattach at 1500000 (this works!)
echo "3. Initializing Bluetooth hardware..."
hciattach /dev/ttyS5 any 1500000 flow &
HCI_PID=$!
echo "Started hciattach with PID: $HCI_PID"
sleep 5

# 4. Check and bring up interface
echo "4. Bringing up interface..."
if hciconfig hci0 2>/dev/null; then
    echo "HCI interface found!"
    hciconfig hci0 up || echo "Note: Interface may already be up"
    sleep 2
    
    # Configure
    echo "5. Configuring Bluetooth..."
    hciconfig hci0 piscan
    hciconfig hci0 name 'RV1106-BT'
    hciconfig hci0 class 0x240404  # Audio device class
    hciconfig hci0 sspmode 1
    
    # Show status
    echo -e "\nBluetooth Status:"
    hciconfig hci0
    
    # 6. Start bluetoothd with experimental flag (for HFP)
    echo -e "\n6. Starting bluetoothd..."
    if [ -f /usr/libexec/bluetooth/bluetoothd ]; then
        /usr/libexec/bluetooth/bluetoothd --experimental --compat -n -d &
        BLUETOOTHD_PID=$!
        sleep 3
    fi
    
    # 7. Add SDP records
    echo -e "\n7. Adding SDP records..."
    sdptool add HF
    sdptool add A2SNK
    
    # 8. Start BlueALSA
    echo -e "\n8. Starting BlueALSA..."
    # First try A2DP only (known to work from PDF)
    bluealsa --profile=a2dp-sink &
    BLUEALSA_PID=$!
    sleep 2
    
    # 9. Start audio player
    echo -e "\n9. Starting audio player..."
    bluealsa-aplay 00:00:00:00:00:00 &
    
    echo -e "\n=== BLUETOOTH READY FOR A2DP ===="
    echo "From the PDF, A2DP works at this point"
    echo ""
    echo "To test:"
    echo "1. Use bluetoothctl to pair:"
    echo "   bluetoothctl"
    echo "   power on"
    echo "   agent on"
    echo "   default-agent"
    echo "   scan on"
    echo "   discoverable on"
    echo "   pairable on"
    echo ""
    echo "2. On phone: pair and connect"
    echo "3. Play music - should work!"
    echo ""
    echo "For HFP (which had issues in PDF):"
    echo "Kill bluealsa and restart with:"
    echo "bluealsa -p a2dp-sink -p hfp-hf --hfp-msc --dbus=org.bluealsa &"
    
else
    echo "ERROR: No HCI interface found"
    echo "hciattach may have failed"
fi

echo -e "\n=== Process Status ==="
ps | grep -E "(hciattach|bluetooth|bluealsa)" | grep -v grep
EOF

adb push /tmp/working_bt_setup.sh /tmp/
adb shell "chmod +x /tmp/working_bt_setup.sh && /tmp/working_bt_setup.sh"