#!/bin/bash
# Working Bluetooth Scanner for RTL8723D

echo "=== RTL8723D Working Scanner ==="

# Function to wait for firmware load
wait_for_firmware() {
    echo "Waiting for firmware to load..."
    for i in {1..30}; do
        if hciconfig hci0 2>/dev/null | grep -q "BD Address: [0-9A-F][0-9A-F]:[0-9A-F][0-9A-F]"; then
            echo "✓ Firmware loaded! MAC address detected"
            return 0
        fi
        sleep 1
        echo -n "."
    done
    echo ""
    return 1
}

# 1. Clean start
echo "1. Cleaning up previous instances..."
killall -q rtkhci rtk_hciattach hciattach 2>/dev/null
sleep 3

# 2. Use the working initialization from earlier
echo "2. Initializing RTL8723D (Method that worked before)..."
if [ -f /tmp/rtk_hciattach ]; then
    echo "Using compiled rtk_hciattach..."
    /tmp/rtk_hciattach -s 115200 /dev/ttyS5 rtk_h5 2>&1 &
    RTK_PID=$!
    
    # Wait for the specific output we saw earlier
    sleep 5
    
    # Look for the firmware load indicators
    for i in {1..10}; do
        if ps -p $RTK_PID > /dev/null 2>&1; then
            echo "rtk_hciattach still running..."
            sleep 2
        else
            echo "rtk_hciattach exited"
            break
        fi
    done
    
    # Check if we got the MAC address (34:75:63:40:51:3D from earlier)
    if hciconfig hci0 2>/dev/null | grep -q "34:75:63:40:51:3D"; then
        echo "✓ SUCCESS! RTL8723D initialized with MAC 34:75:63:40:51:3D"
        
        # Now we can scan!
        echo -e "\n3. Configuring for scanning..."
        hciconfig hci0 up 2>/dev/null || echo "Note: Interface may already be up"
        hciconfig hci0 piscan 2>/dev/null
        hciconfig hci0 sspmode 1 2>/dev/null
        
        echo -e "\n=== Current Bluetooth Status ==="
        hciconfig -a
        
        echo -e "\n=== Scanning for Bluetooth Classic Devices ==="
        echo "Scanning for 15 seconds..."
        hcitool scan
        
        echo -e "\n=== Scanning for Bluetooth LE Devices ==="
        hciconfig hci0 leadv 2>/dev/null
        echo "LE Scanning for 15 seconds..."
        hcitool lescan --duplicates=0 &
        LESCAN_PID=$!
        sleep 15
        kill $LESCAN_PID 2>/dev/null
        
        echo -e "\n=== Device Information ==="
        echo "Local device info:"
        hcitool dev
        
        echo -e "\nConnection info:"
        hcitool con
        
    else
        echo "✗ Firmware load failed - no valid MAC address"
        hciconfig -a
    fi
    
else
    echo "rtk_hciattach not found, cannot initialize RTL8723D properly"
    echo "The standard hciattach doesn't load the firmware correctly"
fi

echo -e "\n=== Scan Complete ==="

# Save results
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="/tmp/bt_scan_${TIMESTAMP}.txt"
echo "Saving results to $RESULT_FILE"

{
    echo "Bluetooth Scan Results - $TIMESTAMP"
    echo "================================="
    echo ""
    echo "HCI Status:"
    hciconfig -a
    echo ""
    echo "Classic Devices Found:"
    hcitool inq 2>/dev/null || echo "No devices found"
    echo ""
    echo "LE Devices Found:"
    hcitool lescan --duplicates=0 2>&1 &
    SAVE_PID=$!
    sleep 5
    kill $SAVE_PID 2>/dev/null
} > $RESULT_FILE

echo "Results saved to: $RESULT_FILE"