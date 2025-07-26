#!/bin/bash
# Complete scanner with working Bluetooth initialization

echo "=== RV1106 Complete Scanner ==="
echo "Initializing and scanning all devices..."
echo ""

# Function to scan serial
scan_serial() {
    echo "[SERIAL DEVICES]"
    ls -la /dev/ttyS* 2>/dev/null | while read line; do
        device=$(echo $line | awk '{print $NF}')
        if [ -c "$device" ]; then
            baud=$(stty -F $device 2>/dev/null | grep -oE "speed [0-9]+" | awk '{print $2}' || echo "N/A")
            echo "  $device - Baud: $baud"
        fi
    done
}

# Function to init Bluetooth
init_bluetooth() {
    echo ""
    echo "[BLUETOOTH INITIALIZATION]"
    
    # Clean up
    killall -q rtkhci rtk_hciattach hciattach 2>/dev/null
    sleep 2
    
    # Reset GPIO
    if [ -d /sys/class/gpio/gpio54 ]; then
        echo 1 > /sys/class/gpio/gpio54/value
        echo "  GPIO 54 (BT wake) set high"
    fi
    
    # Try initialization with high baud rate that worked before
    echo "  Initializing at 1500000 baud..."
    hciattach -s 1500000 /dev/ttyS5 any 1500000 flow &
    HCIATTACH_PID=$!
    sleep 5
    
    # Check if interface exists
    if hciconfig hci0 2>/dev/null | grep -q "BD Address"; then
        echo "  ✓ HCI interface created"
        
        # Try to bring up
        hciconfig hci0 up 2>/dev/null
        hciconfig hci0 piscan 2>/dev/null
        
        # Check final status
        if hciconfig hci0 2>/dev/null | grep -q "UP RUNNING"; then
            echo "  ✓ Bluetooth is UP and RUNNING"
            return 0
        else
            echo "  ✗ Interface exists but not running"
            return 1
        fi
    else
        echo "  ✗ Failed to create HCI interface"
        return 1
    fi
}

# Function to scan Bluetooth
scan_bluetooth() {
    echo ""
    echo "[BLUETOOTH SCAN]"
    
    if ! hciconfig hci0 2>/dev/null | grep -q "UP RUNNING"; then
        echo "  Bluetooth not initialized"
        return
    fi
    
    # Show current status
    echo "  Current Status:"
    hciconfig hci0 | sed 's/^/    /'
    
    # Classic scan
    echo ""
    echo "  Classic Bluetooth Scan (10 sec):"
    hcitool scan 2>&1 | sed 's/^/    /' &
    SCAN_PID=$!
    sleep 10
    kill $SCAN_PID 2>/dev/null
    
    # LE scan
    echo ""
    echo "  BLE Scan (10 sec):"
    hciconfig hci0 leadv 2>/dev/null
    hcitool lescan 2>&1 | sed 's/^/    /' &
    LE_PID=$!
    sleep 10
    kill $LE_PID 2>/dev/null
}

# Main execution
echo "Step 1: Scanning serial devices..."
scan_serial

echo ""
echo "Step 2: Initializing Bluetooth..."
if init_bluetooth; then
    echo ""
    echo "Step 3: Scanning for Bluetooth devices..."
    scan_bluetooth
else
    echo ""
    echo "Step 3: Bluetooth initialization failed"
    echo "Cannot perform Bluetooth scan"
fi

echo ""
echo "=== Scan Complete ==="
echo ""
echo "Summary:"
echo "- Serial ports detected: $(ls /dev/ttyS* 2>/dev/null | wc -l)"
if hciconfig hci0 2>/dev/null | grep -q "UP RUNNING"; then
    echo "- Bluetooth: Active"
else
    echo "- Bluetooth: Not active"
fi

# Save results
LOGFILE="/tmp/scan_results_$(date +%Y%m%d_%H%M%S).log"
{
    echo "RV1106 Scan Results - $(date)"
    echo "======================="
    echo ""
    scan_serial
    echo ""
    hciconfig -a 2>/dev/null || echo "No Bluetooth interface"
} > $LOGFILE

echo ""
echo "Results saved to: $LOGFILE"