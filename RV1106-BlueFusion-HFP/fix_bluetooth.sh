#!/bin/sh
# Direct fix for RTL8723D on RV1106

echo "Fixing RTL8723D Bluetooth..."

# Kill everything
killall hciattach btattach bluealsa 2>/dev/null
sleep 1

# Remove and recreate HCI
rm -f /dev/hci* 2>/dev/null

# Try btattach with H4 protocol
echo "Trying btattach..."
btattach -B /dev/ttyS5 -P h4 -S 1500000 &
BTPID=$!
sleep 3

# Check if it worked
if hciconfig hci0 2>/dev/null | grep -q "Type:"; then
    echo "HCI created, initializing..."
    
    # Send HCI Reset
    hcitool cmd 0x03 0x0003
    sleep 1
    
    # Try to bring up
    hciconfig hci0 up
    sleep 1
    
    # Check again
    hciconfig hci0
    
    # If MAC is still 00:00:00:00:00:00, try firmware load
    MAC=$(hciconfig hci0 | grep "BD Address" | awk '{print $3}')
    if [ "$MAC" = "00:00:00:00:00:00" ]; then
        echo "Firmware not loaded, trying manual load..."
        
        # Download firmware command
        hcitool cmd 0x3f 0x0001 0x01
        sleep 0.5
        
        # Reset again
        hcitool cmd 0x03 0x0003
        sleep 2
    fi
    
    # Final status
    echo "Final status:"
    hciconfig -a
else
    echo "Failed to create HCI interface"
    kill $BTPID 2>/dev/null
fi