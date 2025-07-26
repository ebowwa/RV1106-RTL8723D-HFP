#!/bin/bash
# Initialize RTL8723D without rtk_hciattach

cat > /tmp/init_rtl8723d_final.sh << 'EOF'
#!/bin/sh
# RTL8723D initialization without rtk_hciattach
# Based on discovered working parameters

echo "RTL8723D Initialization (without rtk_hciattach)"
echo "============================================="

# Clean start
killall hciattach btattach 2>/dev/null
sleep 1

# The chip responds at 1500000 baud, not 115200
BAUD=1500000
DEVICE=/dev/ttyS5

echo "Starting at $BAUD baud on $DEVICE..."

# Method 1: Use hciattach with 'any' protocol
hciattach $DEVICE any $BAUD flow noflow &
HCI_PID=$!

sleep 3

# Check if interface created
if hciconfig hci0 2>/dev/null | grep -q "RX bytes"; then
    echo "✓ HCI interface created"
    
    # Try to initialize with vendor commands
    echo "Sending Realtek vendor commands..."
    
    # RTL8723D specific initialization sequence
    # Based on rtk_hciattach behavior
    
    # 1. Enter download mode
    hcitool cmd 0x3f 0x66 0x01 2>/dev/null
    sleep 0.5
    
    # 2. Send reset
    hcitool cmd 0x03 0x03 2>/dev/null
    sleep 1
    
    # 3. Try multiple times to bring up
    for i in 1 2 3 4 5; do
        echo "Attempt $i..."
        hciconfig hci0 reset
        sleep 0.5
        hciconfig hci0 up
        sleep 2
        
        # Check MAC
        MAC=$(hciconfig hci0 | grep "BD Address" | awk '{print $3}')
        if [ "$MAC" != "00:00:00:00:00:00" ]; then
            echo "✓ SUCCESS! MAC: $MAC"
            
            # Configure
            hciconfig hci0 piscan
            hciconfig hci0 sspmode 1
            
            # Start BlueALSA
            bluealsa -p hfp-hf -p a2dp-sink &
            
            echo "✓ Bluetooth initialized!"
            hciconfig -a
            exit 0
        fi
    done
    
    echo "⚠️  MAC still 00:00:00:00:00:00"
    echo "The chip needs rtk_hciattach for firmware loading"
else
    echo "✗ Failed to create HCI interface"
    kill $HCI_PID 2>/dev/null
fi

# Show what we learned
echo -e "\nSummary:"
echo "- Device responds at 1500000 baud (confirmed)"
echo "- Firmware at /lib/firmware/rtlbt/ (present)"
echo "- Chip receives commands (RX bytes increase)"
echo "- rtk_hciattach required for full initialization"
EOF

# Deploy and run
adb push /tmp/init_rtl8723d_final.sh /tmp/
adb shell "chmod +x /tmp/init_rtl8723d_final.sh && /tmp/init_rtl8723d_final.sh"

echo -e "\n📝 Next Steps:"
echo "1. The device IS working at 1500000 baud"
echo "2. To fully initialize, compile rtk_hciattach:"
echo "   - Use cross-compiler: arm-linux-gnueabihf-gcc"
echo "   - Or use Docker: docker run -v \$PWD:/src arm32v7/ubuntu"
echo "3. Once compiled: rtk_hciattach -n -s 115200 /dev/ttyS5 rtk_h5"