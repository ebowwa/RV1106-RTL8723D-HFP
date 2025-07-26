#!/bin/sh
# Initialize RTL8723D Bluetooth on RV1106
# Run this script on the device via ADB

echo "=== RTL8723D Bluetooth Initialization ==="

# 1. Check firmware
echo "[1/6] Checking firmware..."
if [ -f /lib/firmware/rtlbt/rtl8723d_fw ]; then
    echo "✓ Firmware found: rtl8723d_fw"
    ls -la /lib/firmware/rtlbt/rtl8723d*
else
    echo "✗ Firmware missing!"
    exit 1
fi

# 2. Kill any existing attach processes
echo -e "\n[2/6] Cleaning up old processes..."
killall hciattach 2>/dev/null
killall btattach 2>/dev/null
sleep 1

# 3. Configure UART
echo -e "\n[3/6] Configuring UART /dev/ttyS5..."
stty -F /dev/ttyS5 115200 raw -echo -echoe -echok -echoctl -echoke

# 4. Try different attach methods
echo -e "\n[4/6] Attaching RTL8723D..."

# Method 1: Try Realtek-specific attach
echo "Trying rtk_h5 protocol..."
hciattach /dev/ttyS5 rtk_h5 115200 flow 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Success with rtk_h5"
else
    # Method 2: Try generic H5
    echo "Trying generic H5 protocol..."
    btattach -B /dev/ttyS5 -P h5 -S 115200 &
    BTPID=$!
    sleep 3
    
    # Check if it worked
    if ! hciconfig hci0 2>/dev/null; then
        kill $BTPID 2>/dev/null
        
        # Method 3: Try H4
        echo "Trying H4 protocol..."
        btattach -B /dev/ttyS5 -P h4 -S 115200 &
        BTPID=$!
        sleep 3
    fi
fi

# 5. Check result
echo -e "\n[5/6] Checking HCI interface..."
if hciconfig hci0 2>&1 | grep -q "hci0"; then
    echo "✓ HCI interface created!"
    hciconfig hci0 up
    hciconfig hci0
else
    echo "✗ No HCI interface found"
    echo "Checking dmesg for errors..."
    dmesg | grep -i "bluetooth\|hci\|rtl8723" | tail -10
    exit 1
fi

# 6. Enable and test
echo -e "\n[6/6] Enabling Bluetooth..."
hciconfig hci0 piscan
hciconfig hci0 sspmode 1
hciconfig hci0 name "RV1106-RTL8723D"

echo -e "\n=== Initialization Complete ==="
echo "Bluetooth interface:"
hciconfig -a

echo -e "\nTo test:"
echo "1. Scan: hcitool scan"
echo "2. Info: hcitool dev"
echo "3. BlueALSA: bluealsa -p hfp-hf --hfp-codec=cvsd"