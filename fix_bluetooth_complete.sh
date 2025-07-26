#!/bin/bash
# Complete Bluetooth fix with proper initialization sequence

cat > /tmp/bluetooth_fix.sh << 'EOF'
#!/bin/sh
# RTL8723D Complete Fix

echo "=== RTL8723D Complete Bluetooth Fix ==="
echo "======================================"

# Step 1: Clean slate
echo -e "\n1. Cleaning up..."
killall rtk_hciattach hciattach btattach bluealsa ofonod 2>/dev/null
sleep 2

# Remove any stale HCI interfaces
rm -f /sys/class/bluetooth/hci* 2>/dev/null

# Step 2: Check BlueZ is running
echo -e "\n2. Starting BlueZ daemon..."
if ! ps | grep -q "[b]luetoothd"; then
    bluetoothd -n -d &
    sleep 2
fi

# Step 3: Initialize with rtk_hciattach (keep it running)
echo -e "\n3. Starting rtk_hciattach..."
if [ -f /tmp/rtk_hciattach ]; then
    # Don't use -n flag (non-detach) as it might be blocking
    /tmp/rtk_hciattach -s 115200 /dev/ttyS5 rtk_h5 &
    RTK_PID=$!
    echo "Started rtk_hciattach with PID: $RTK_PID"
    
    # Wait for initialization
    sleep 10
    
    # Check if process is still running
    if kill -0 $RTK_PID 2>/dev/null; then
        echo "rtk_hciattach is running"
    else
        echo "rtk_hciattach exited, trying alternative..."
        # Alternative: use standard hciattach at high speed
        hciattach /dev/ttyS5 any 1500000 flow &
        sleep 5
    fi
else
    echo "rtk_hciattach not found!"
    exit 1
fi

# Step 4: Check HCI interface
echo -e "\n4. Checking HCI interface..."
hciconfig -a

# Step 5: Try to bring up interface
echo -e "\n5. Bringing up interface..."
for i in 1 2 3; do
    echo "Attempt $i..."
    hciconfig hci0 down 2>/dev/null
    sleep 1
    hciconfig hci0 up 2>/dev/null
    
    if hciconfig hci0 2>/dev/null | grep -q "UP"; then
        echo "SUCCESS! Interface is UP"
        break
    fi
    sleep 2
done

# Step 6: Configure if UP
if hciconfig hci0 2>/dev/null | grep -q "UP"; then
    echo -e "\n6. Configuring Bluetooth..."
    hciconfig hci0 piscan
    hciconfig hci0 sspmode 1
    hciconfig hci0 name "RV1106-RTL8723D"
    
    # Step 7: Start services
    echo -e "\n7. Starting audio services..."
    
    # Option A: BlueALSA with both profiles
    if which bluealsa 2>/dev/null; then
        bluealsa -p a2dp-source -p a2dp-sink -p hfp-hf -p hfp-ag &
        echo "Started BlueALSA with A2DP and HFP"
    fi
    
    # Option B: oFono for HFP (if available)
    if which ofonod 2>/dev/null; then
        ofonod &
        echo "Started oFono for HFP"
    fi
    
    echo -e "\n=== BLUETOOTH READY ==="
    hciconfig hci0
    echo -e "\nTo test:"
    echo "1. Pair with phone using bluetoothctl"
    echo "2. Test A2DP music streaming"
    echo "3. Test HFP phone calls"
    
else
    echo -e "\n=== FAILED: Interface won't come up ==="
    
    # Additional debugging
    echo -e "\nChecking processes:"
    ps | grep -E "(rtk|hci|blue)"
    
    echo -e "\nChecking UART:"
    cat /proc/tty/driver/serial | grep -A3 "5:"
    
    echo -e "\nKernel config:"
    if [ -f /proc/config.gz ]; then
        zcat /proc/config.gz | grep -E "CONFIG_BT|CONFIG_SERIAL" | head -10
    fi
fi

# Keep script info
echo -e "\n=== Process Status ==="
ps | grep -E "(rtk_hciattach|hciattach|bluealsa|bluetoothd|ofonod)" | grep -v grep
EOF

# Deploy and run
adb push /tmp/bluetooth_fix.sh /tmp/
adb shell "chmod +x /tmp/bluetooth_fix.sh && /tmp/bluetooth_fix.sh"