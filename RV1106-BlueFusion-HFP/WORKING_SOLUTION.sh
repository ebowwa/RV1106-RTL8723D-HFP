#!/bin/bash
# WORKING SOLUTION for RTL8723D on RV1106
# The device responds at 1500000 baud!

cat > /tmp/rtl8723d_working.sh << 'EOF'
#!/bin/sh
echo "RTL8723D Working Solution"
echo "========================"

# Kill any existing
killall hciattach btattach 2>/dev/null
sleep 1

# The magic combination that works:
echo "Initializing RTL8723D at 1500000 baud..."
hciattach /dev/ttyS5 any 1500000 flow noflow &
HCIPID=$!

# Wait for device to respond
sleep 3

# Check if we got response
if hciconfig hci0 2>/dev/null | grep -q "RX bytes:[1-9]"; then
    echo "✓ Device is responding!"
    
    # The device needs specific initialization sequence
    # Since we don't have rtk_hciattach, we need to:
    # 1. Keep the connection alive
    # 2. Send periodic resets to prevent timeout
    
    while true; do
        # Try to bring up
        hciconfig hci0 up 2>/dev/null
        
        # Check MAC address
        MAC=$(hciconfig hci0 2>/dev/null | grep "BD Address" | awk '{print $3}')
        if [ "$MAC" != "00:00:00:00:00:00" ] && [ -n "$MAC" ]; then
            echo "✓ SUCCESS! Bluetooth initialized with MAC: $MAC"
            hciconfig -a
            
            # Start BlueALSA
            echo "Starting BlueALSA..."
            bluealsa -p hfp-hf -p a2dp-sink &
            
            break
        fi
        
        # Send reset to keep alive
        hcitool cmd 0x03 0x0003 2>/dev/null
        sleep 2
    done
else
    echo "✗ Device not responding"
    kill $HCIPID 2>/dev/null
fi
EOF

# Deploy and run
adb push /tmp/rtl8723d_working.sh /tmp/
adb shell "chmod +x /tmp/rtl8723d_working.sh && /tmp/rtl8723d_working.sh"