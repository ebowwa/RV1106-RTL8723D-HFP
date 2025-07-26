#!/bin/bash
# Initialize Bluetooth and run scanner

echo "=== Initializing Bluetooth for Scanning ==="

# 1. Kill any existing processes
echo "1. Cleaning up..."
killall -q rtkhci rtk_hciattach hciattach bluetoothd bluealsa 2>/dev/null
sleep 2

# 2. Reset the UART
echo "2. Resetting UART..."
stty -F /dev/ttyS5 0 2>/dev/null
sleep 1

# 3. Initialize with standard hciattach (we know this works at 1500000)
echo "3. Initializing RTL8723D..."
hciattach -s 1500000 /dev/ttyS5 any 1500000 flow &
HCI_PID=$!
echo "Started hciattach with PID: $HCI_PID"
sleep 5

# 4. Check if interface exists
if hciconfig hci0 2>/dev/null; then
    echo "4. HCI interface detected, bringing up..."
    
    # Try to bring up the interface
    hciconfig hci0 up
    sleep 2
    
    # Check if it came up
    if hciconfig hci0 | grep -q "UP RUNNING"; then
        echo "✓ Bluetooth interface is UP!"
        
        # Configure for scanning
        hciconfig hci0 piscan
        hciconfig hci0 name 'RV1106-Scanner'
        hciconfig hci0 class 0x000000  # Generic device
        
        # Show current status
        echo -e "\n=== Bluetooth Status ==="
        hciconfig hci0
        
        # Now run the scanner
        echo -e "\n=== Running Scanner ==="
        /tmp/device_scanner.sh
        
    else
        echo "✗ Interface exists but won't come UP"
        echo "Trying firmware loading..."
        
        # Kill current hciattach
        kill $HCI_PID 2>/dev/null
        sleep 2
        
        # Try with rtk_hciattach if available
        if [ -f /tmp/rtk_hciattach ]; then
            echo "Using rtk_hciattach to load firmware..."
            /tmp/rtk_hciattach -s 115200 /dev/ttyS5 rtk_h5 &
            RTK_PID=$!
            
            # Wait for firmware to load
            echo "Waiting for firmware load (this shows MAC address)..."
            sleep 15
            
            # Check if we got a MAC address
            if hciconfig hci0 2>/dev/null | grep -v "00:00:00:00:00:00"; then
                echo "✓ Firmware loaded, MAC address assigned!"
                
                # Now restart with standard hciattach
                kill $RTK_PID 2>/dev/null
                sleep 2
                
                echo "Restarting with standard hciattach..."
                hciattach -s 1500000 /dev/ttyS5 any 1500000 flow &
                sleep 5
                
                hciconfig hci0 up
                hciconfig hci0 piscan
                
                # Run scanner
                echo -e "\n=== Running Scanner with initialized Bluetooth ==="
                /tmp/device_scanner.sh
            else
                echo "✗ Firmware load failed"
            fi
            
        elif [ -f /userdata/rtkhci ]; then
            echo "Using rtkhci to load firmware..."
            cd /userdata
            ./rtkhci -n -s 115200 /dev/ttyS5 rtk_h5 &
            sleep 15
            
            # Check and continue as above
            if hciconfig hci0 2>/dev/null | grep -v "00:00:00:00:00:00"; then
                echo "✓ Firmware loaded!"
                /tmp/device_scanner.sh
            fi
        else
            echo "No Realtek initialization tools available"
            echo "Bluetooth may not work properly without firmware"
        fi
    fi
else
    echo "✗ No HCI interface created"
    echo "Hardware initialization failed"
fi

echo -e "\n=== Initialization Complete ==="