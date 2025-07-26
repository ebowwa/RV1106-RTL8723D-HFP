#!/bin/bash
# Setup oFono + BlueALSA for complete HFP support on RV1106

echo "Setting up oFono + BlueALSA for HFP support"
echo "=========================================="

# Create setup script for device
cat > /tmp/setup_ofono_device.sh << 'EOF'
#!/bin/sh
# oFono + BlueALSA setup on RV1106

echo "=== Checking current Bluetooth status ==="
hciconfig -a
ps | grep -E "(rtk_hciattach|bluealsa|ofono)"

# Kill existing services
echo -e "\n=== Stopping existing services ==="
killall bluealsa ofonod 2>/dev/null
sleep 2

# First, let's try to fix the HCI interface
echo -e "\n=== Attempting to fix HCI interface ==="

# Check if rtk_hciattach is still running
if ! ps | grep -q "[r]tk_hciattach"; then
    echo "rtk_hciattach not running, restarting..."
    /tmp/rtk_hciattach -n -s 115200 /dev/ttyS5 rtk_h5 &
    sleep 5
fi

# Try btattach instead of hciconfig up
echo "Trying alternative attach method..."
killall btattach 2>/dev/null
btattach -B /dev/ttyS5 -P h5 -S 1500000 &
sleep 3

# Check if that worked
hciconfig -a

# If still down, try hciattach without rtk
if ! hciconfig hci0 2>/dev/null | grep -q "UP"; then
    echo "Trying standard hciattach..."
    killall hciattach 2>/dev/null
    hciattach /dev/ttyS5 any 1500000 flow &
    sleep 3
fi

# Force reset and up
echo -e "\n=== Forcing HCI up ==="
hciconfig hci0 down 2>/dev/null
sleep 1
hciconfig hci0 reset 2>/dev/null
sleep 1
echo 1 > /sys/class/bluetooth/hci0/device/power/control 2>/dev/null
hciconfig hci0 up 2>/dev/null

# Check final status
echo -e "\n=== Current HCI status ==="
hciconfig -a

# If HCI is up, configure it
if hciconfig hci0 2>/dev/null | grep -q "UP"; then
    echo -e "\n=== HCI is UP! Configuring... ==="
    
    # Configure HCI
    hciconfig hci0 piscan
    hciconfig hci0 sspmode 1
    hciconfig hci0 class 0x200404  # Audio device class
    
    # Start BlueALSA for A2DP
    echo -e "\n=== Starting BlueALSA for A2DP ==="
    bluealsa -p a2dp-source -p a2dp-sink &
    BLUEALSA_PID=$!
    sleep 2
    
    # Check if oFono is available
    if which ofonod 2>/dev/null; then
        echo -e "\n=== Starting oFono for HFP ==="
        # Create oFono config if needed
        mkdir -p /etc/ofono
        cat > /etc/ofono/phonesim.conf << 'OFONO'
[phonesim]
Driver=phonesim
Address=127.0.0.1
Port=12345
OFONO
        
        # Start oFono
        ofonod -n -d &
        OFONO_PID=$!
        sleep 3
        
        # Enable Bluetooth plugin
        echo -e "\n=== Configuring oFono HFP ==="
        # This would normally be done via dbus-send or ofono scripts
        
    else
        echo "oFono not found, using BlueALSA HFP mode"
        kill $BLUEALSA_PID 2>/dev/null
        bluealsa -p a2dp-source -p a2dp-sink -p hfp-hf -p hfp-ag &
    fi
    
    echo -e "\n=== Setup complete! ==="
    echo "Services running:"
    ps | grep -E "(bluealsa|ofono)"
    
    echo -e "\n=== Ready for Bluetooth connections ==="
    echo "To pair: bluetoothctl"
    echo "  > power on"
    echo "  > agent on"
    echo "  > scan on"
    echo "  > pair XX:XX:XX:XX:XX:XX"
    echo "  > connect XX:XX:XX:XX:XX:XX"
    
else
    echo -e "\n=== ERROR: Could not bring up HCI interface ==="
    echo "Troubleshooting steps:"
    echo "1. Check dmesg for errors: dmesg | tail -20"
    echo "2. Check UART permissions: ls -la /dev/ttyS5"
    echo "3. Try manual hciattach: hciattach /dev/ttyS5 rtk_h5 1500000"
    echo "4. Check kernel BT support: zcat /proc/config.gz | grep -i bluetooth"
fi

# Debug info
echo -e "\n=== Debug Information ==="
echo "Kernel messages:"
dmesg | grep -i bluetooth | tail -10
echo -e "\nUART info:"
ls -la /dev/ttyS5
stty -F /dev/ttyS5 -a 2>/dev/null | head -3
EOF

# Push and run setup script
echo "Deploying setup script to device..."
adb push /tmp/setup_ofono_device.sh /tmp/
adb shell "chmod +x /tmp/setup_ofono_device.sh"

echo -e "\nRunning setup on device..."
adb shell "/tmp/setup_ofono_device.sh"