#!/bin/sh
# Alternative RTL8723D initialization using btrtl

echo "=== RTL8723D Bluetooth Init v2 ==="

# Kill old processes
killall hciattach btattach 2>/dev/null
sleep 1

# Method 1: Try with explicit firmware path
echo "[1/3] Trying hciattach with firmware path..."
export FIRMWARE_DIR=/lib/firmware/rtlbt
hciattach -n /dev/ttyS5 rtk_h4 115200 flow &
HCI_PID=$!

sleep 5

# Check if it worked
if hciconfig hci0 2>/dev/null | grep -q "BD Address"; then
    echo "✓ Success!"
    kill $HCI_PID 2>/dev/null
    hciconfig hci0 up
else
    kill $HCI_PID 2>/dev/null
    
    # Method 2: Try different baud rates
    echo "[2/3] Trying different baud rates..."
    for BAUD in 1500000 921600 460800 230400 115200; do
        echo "Testing $BAUD baud..."
        hciattach /dev/ttyS5 any $BAUD flow noflow 2>&1
        sleep 2
        
        if hciconfig hci0 2>/dev/null | grep -q "BD Address"; then
            echo "✓ Success at $BAUD baud!"
            hciconfig hci0 up
            break
        fi
    done
fi

# Method 3: Manual firmware load
if ! hciconfig hci0 2>/dev/null | grep -q "UP"; then
    echo "[3/3] Trying manual approach..."
    
    # Configure UART
    stty -F /dev/ttyS5 115200 cs8 -cstopb -parenb -crtscts
    
    # Try btattach with bcsp protocol (common for UART BT)
    btattach -B /dev/ttyS5 -P bcsp -S 115200 &
    sleep 3
fi

# Final check
echo -e "\n=== Final Status ==="
if hciconfig -a 2>/dev/null | grep -q "hci0"; then
    hciconfig -a
    echo -e "\n✓ Bluetooth initialized!"
    
    # Try to get device info
    echo -e "\nDevice info:"
    hciconfig hci0 version
    hciconfig hci0 revision
else
    echo "✗ Failed to initialize Bluetooth"
    echo -e "\nDebugging info:"
    dmesg | grep -i "uart\|tty\|bluetooth\|hci" | tail -15
fi