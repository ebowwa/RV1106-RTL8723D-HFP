#!/bin/bash
# Power cycle approach for RTL8723D

cat > /tmp/power_cycle_bt.sh << 'EOF'
#!/bin/sh
# RTL8723D Power Cycle Fix

echo "=== RTL8723D Power Cycle Fix ==="

# 1. Complete cleanup
echo "1. Cleaning up all BT processes..."
killall -9 rtk_hciattach hciattach btattach bluealsa bluetoothd 2>/dev/null
sleep 2

# 2. Reset UART
echo "2. Resetting UART..."
# Try to reset UART settings
stty -F /dev/ttyS5 sane 2>/dev/null
stty -F /dev/ttyS5 115200 cs8 -cstopb -parenb 2>/dev/null

# 3. Check for Bluetooth power control
echo "3. Looking for BT power control..."
if [ -f /sys/class/rfkill/rfkill0/state ]; then
    echo "Found rfkill, cycling power..."
    echo 0 > /sys/class/rfkill/rfkill0/state
    sleep 2
    echo 1 > /sys/class/rfkill/rfkill0/state
    sleep 2
fi

# Look for GPIO control
for gpio in /sys/class/gpio/gpio*; do
    if [ -d "$gpio" ] && grep -q "bt" "$gpio/label" 2>/dev/null; then
        echo "Found BT GPIO: $gpio"
        echo 0 > "$gpio/value"
        sleep 2
        echo 1 > "$gpio/value"
        sleep 2
    fi
done

# 4. Try different initialization approaches
echo -e "\n4. Trying initialization methods..."

# Method A: Standard hciattach at high speed first
echo "Method A: Standard hciattach at 1500000..."
hciattach /dev/ttyS5 any 1500000 flow &
HCI_PID=$!
sleep 5

if hciconfig hci0 2>/dev/null; then
    echo "SUCCESS with standard hciattach!"
    hciconfig hci0 up
    hciconfig -a
else
    echo "Failed, killing process..."
    kill $HCI_PID 2>/dev/null
    sleep 2
    
    # Method B: Try H4 protocol
    echo -e "\nMethod B: H4 protocol..."
    hciattach /dev/ttyS5 rtk_h4 115200 flow &
    HCI_PID=$!
    sleep 5
    
    if hciconfig hci0 2>/dev/null; then
        echo "SUCCESS with H4 protocol!"
        hciconfig hci0 up
        hciconfig -a
    else
        kill $HCI_PID 2>/dev/null
        sleep 2
        
        # Method C: btattach
        echo -e "\nMethod C: btattach..."
        btattach -B /dev/ttyS5 -P h4 -S 1500000 &
        sleep 5
        
        if hciconfig hci0 2>/dev/null; then
            echo "SUCCESS with btattach!"
            hciconfig hci0 up
            hciconfig -a
        fi
    fi
fi

# 5. If we have an interface, configure it
if hciconfig hci0 2>/dev/null | grep -E "(UP|DOWN)"; then
    echo -e "\n5. Configuring Bluetooth..."
    
    # Try to bring up if down
    hciconfig hci0 up 2>/dev/null || true
    
    # Configure
    hciconfig hci0 piscan
    hciconfig hci0 sspmode 1
    
    # Start BlueALSA
    echo "Starting BlueALSA..."
    bluealsa -p a2dp-source -p a2dp-sink -p hfp-hf -p hfp-ag &
    
    echo -e "\n=== BLUETOOTH READY ==="
    hciconfig hci0
    
    # Test scan
    echo -e "\nTesting scan..."
    hcitool scan &
    SCAN_PID=$!
    sleep 10
    kill $SCAN_PID 2>/dev/null
else
    echo -e "\n=== FAILED: No HCI interface ==="
    echo "The RTL8723D might need:"
    echo "1. Proper device tree configuration"
    echo "2. Kernel module: CONFIG_BT_HCIUART_RTL"
    echo "3. Manual firmware upload via rtk_hciattach"
    
    # Last resort: try rtk_hciattach one more time
    echo -e "\nLast attempt with rtk_hciattach..."
    /tmp/rtk_hciattach -s 115200 /dev/ttyS5 rtk_h5
fi

echo -e "\n=== Final Status ==="
hciconfig -a 2>/dev/null || echo "No HCI interface found"
ps | grep -E "(hciattach|btattach|bluealsa)" | grep -v grep
EOF

# Deploy and run
adb push /tmp/power_cycle_bt.sh /tmp/
adb shell "chmod +x /tmp/power_cycle_bt.sh && /tmp/power_cycle_bt.sh"