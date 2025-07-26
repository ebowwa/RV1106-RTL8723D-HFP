#!/bin/bash
# Fixed Bluetooth initialization for RTL8723D

echo "=== RTL8723D Bluetooth Fix ==="

# 1. Complete cleanup
echo "1. Complete cleanup..."
killall -9 rtkhci rtk_hciattach hciattach bluetoothd 2>/dev/null
rmmod hci_uart 2>/dev/null
rmmod btrtl 2>/dev/null
rmmod bluetooth 2>/dev/null
sleep 3

# 2. GPIO Reset (from device tree findings)
echo "2. GPIO reset sequence..."
# GPIO 54 is 0x36 from device tree (BT wake)
# GPIO 54 + 11 = GPIO 65 for BT enable
if [ ! -d /sys/class/gpio/gpio65 ]; then
    echo 65 > /sys/class/gpio/export 2>/dev/null
fi

if [ -d /sys/class/gpio/gpio65 ]; then
    echo out > /sys/class/gpio/gpio65/direction
    echo 0 > /sys/class/gpio/gpio65/value
    sleep 0.5
    echo 1 > /sys/class/gpio/gpio65/value
    echo "GPIO 65 toggled for BT reset"
fi

# Also try GPIO 54 (BT wake)
if [ ! -d /sys/class/gpio/gpio54 ]; then
    echo 54 > /sys/class/gpio/export 2>/dev/null
fi

if [ -d /sys/class/gpio/gpio54 ]; then
    echo out > /sys/class/gpio/gpio54/direction
    echo 1 > /sys/class/gpio/gpio54/value
    echo "GPIO 54 set high for BT wake"
fi

sleep 2

# 3. Load kernel modules if available
echo "3. Loading kernel modules..."
modprobe bluetooth 2>/dev/null
modprobe btrtl 2>/dev/null
modprobe hci_uart 2>/dev/null

# 4. Check for existing binaries
echo "4. Checking for initialization binaries..."
if [ -f /userdata/rtkhci ]; then
    echo "Found rtkhci at /userdata/rtkhci"
    INIT_CMD="/userdata/rtkhci"
elif [ -f /tmp/rtk_hciattach ]; then
    echo "Found rtk_hciattach at /tmp/rtk_hciattach"
    INIT_CMD="/tmp/rtk_hciattach"
else
    echo "No Realtek init binary found, using standard hciattach"
    INIT_CMD="hciattach"
fi

# 5. Try different initialization sequences
echo -e "\n5. Trying initialization sequences..."

# Method 1: Direct H4 protocol (simpler than H5)
echo "Method 1: H4 protocol at 115200..."
$INIT_CMD -s 115200 /dev/ttyS5 rtk_h4 115200 flow &
INIT_PID=$!
sleep 8

if hciconfig hci0 2>/dev/null | grep -q "BD Address"; then
    echo "✓ Method 1 successful!"
else
    kill $INIT_PID 2>/dev/null
    sleep 2
    
    # Method 2: Standard any protocol at high speed
    echo "Method 2: Any protocol at 1500000..."
    hciattach /dev/ttyS5 any 1500000 flow &
    INIT_PID=$!
    sleep 5
    
    if hciconfig hci0 2>/dev/null; then
        echo "✓ Method 2 successful!"
    else
        kill $INIT_PID 2>/dev/null
        sleep 2
        
        # Method 3: Bruteforce with btattach
        echo "Method 3: Using btattach..."
        btattach -B /dev/ttyS5 -P h4 -S 115200 &
        INIT_PID=$!
        sleep 5
        
        if hciconfig hci0 2>/dev/null; then
            echo "✓ Method 3 successful!"
        fi
    fi
fi

# 6. Check final status
echo -e "\n6. Final status check..."
if hciconfig hci0 2>/dev/null; then
    # Try to bring up
    hciconfig hci0 up 2>/dev/null
    sleep 2
    
    # Get detailed info
    echo "=== HCI Status ==="
    hciconfig -a
    
    # Check if we can actually scan
    echo -e "\n=== Testing scan capability ==="
    timeout 5 hcitool scan
    
    echo -e "\n=== Running full scanner ==="
    /tmp/device_scanner.sh
else
    echo "✗ No HCI interface available"
    echo "Bluetooth initialization failed"
    
    # Debug info
    echo -e "\nDebug information:"
    dmesg | tail -20 | grep -E "(Bluetooth|hci|uart|tty)" || echo "No relevant kernel messages"
fi