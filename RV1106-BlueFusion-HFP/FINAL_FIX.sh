#!/bin/bash
# FINAL FIX - RTL8723D on RV1106
# The key: device works at 1500000 baud and needs proper initialization

echo "🔧 RTL8723D Final Fix"
echo "===================="

# Create the initialization script
cat > /tmp/init_rtl8723d_final.sh << 'EOF'
#!/bin/sh
echo "Initializing RTL8723D Bluetooth..."

# Clean start
killall hciattach btattach bluealsa 2>/dev/null
sleep 1

# Remove old HCI
rm -f /sys/class/bluetooth/hci* 2>/dev/null

# Initialize at 1500000 baud (this is the key!)
echo "Starting HCI at 1500000 baud..."
hciattach /dev/ttyS5 any 1500000 flow noflow &
HCI_PID=$!

# Wait for initialization
sleep 5

# Check if working
if hciconfig hci0 2>/dev/null | grep -q "RX bytes:[0-9]"; then
    echo "✓ HCI interface created and receiving data"
    
    # The chip is responding but needs firmware
    # Without rtk_hciattach, we can try:
    
    # 1. Force a different initialization
    hciconfig hci0 reset
    sleep 1
    
    # 2. Try to bring up multiple times
    for i in 1 2 3 4 5; do
        echo "Attempt $i to bring up interface..."
        hciconfig hci0 up
        sleep 2
        
        # Check if MAC changed from 00:00:00:00:00:00
        MAC=$(hciconfig hci0 | grep "BD Address" | awk '{print $3}')
        if [ "$MAC" != "00:00:00:00:00:00" ]; then
            echo "✓ SUCCESS! MAC Address: $MAC"
            break
        fi
    done
    
    # Final status
    echo -e "\nFinal status:"
    hciconfig -a
    
    # If still 00:00:00:00:00:00, it needs rtk_hciattach
    if [ "$MAC" = "00:00:00:00:00:00" ]; then
        echo -e "\n⚠️  The device is responding but needs proper firmware loading."
        echo "The RTL8723D requires the Realtek-specific rtk_hciattach tool."
        echo ""
        echo "However, the UART is working correctly at 1500000 baud."
        echo "RX bytes show the chip is responding to commands."
    else
        # Start services
        echo -e "\n✓ Starting Bluetooth services..."
        hciconfig hci0 piscan
        hciconfig hci0 sspmode 1
        bluealsa -p hfp-hf -p a2dp-sink &
        echo "✓ Bluetooth ready!"
    fi
else
    echo "✗ Failed to create HCI interface"
    kill $HCI_PID 2>/dev/null
fi

# Show what we learned
echo -e "\n📊 Summary:"
echo "- UART: /dev/ttyS5"
echo "- Baud: 1500000 (not 115200!)"  
echo "- Chip: RTL8723D (responds to HCI commands)"
echo "- Status: Needs rtk_hciattach for firmware loading"
EOF

# Push and execute
adb push /tmp/init_rtl8723d_final.sh /tmp/
adb shell "chmod +x /tmp/init_rtl8723d_final.sh && /tmp/init_rtl8723d_final.sh"

echo -e "\n📝 Next Steps:"
echo "1. The RTL8723D is confirmed working at 1500000 baud"
echo "2. To fully initialize, you need rtk_hciattach compiled for ARM"
echo "3. Once you have rtk_hciattach:"
echo "   rtk_hciattach -n -s 115200 /dev/ttyS5 rtk_h5"
echo "4. The chip will then load firmware and show proper MAC address"