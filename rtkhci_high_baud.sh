#!/bin/bash
# Try rtkhci with high baud rate

cat > /tmp/rtkhci_high_baud.sh << 'EOF'
#!/bin/sh
# Try rtkhci with 1500000 baud

echo "=== rtkhci with 1500000 baud ==="

# Clean up
killall -q rtkhci rtk_hciattach hciattach 2>/dev/null
sleep 2

# First, try standard hciattach to see if device responds
echo "Testing if device responds at 1500000..."
hciattach /dev/ttyS5 any 1500000 flow &
HCI_PID=$!
sleep 5
if hciconfig hci0 2>/dev/null; then
    echo "Device responds at 1500000!"
    kill $HCI_PID 2>/dev/null
    sleep 2
else
    kill $HCI_PID 2>/dev/null
fi

# Now try rtkhci with different parameters
echo -e "\nTrying rtkhci variations:"

# Try without H5 protocol
echo -e "\n1. rtkhci without protocol specified:"
cd /userdata
./rtkhci -n -s 1500000 /dev/ttyS5 &
RTKHCI_PID=$!
sleep 8
kill $RTKHCI_PID 2>/dev/null
hciconfig -a

# Try with H4 protocol
echo -e "\n2. rtkhci with H4 protocol:"
./rtkhci -n -s 115200 /dev/ttyS5 rtk_h4 &
RTKHCI_PID=$!
sleep 8
kill $RTKHCI_PID 2>/dev/null
hciconfig -a

# Try without -n flag (let it detach)
echo -e "\n3. rtkhci without -n flag:"
./rtkhci -s 115200 /dev/ttyS5 rtk_h5
sleep 5
hciconfig -a

# Check what's running
echo -e "\n=== Process Status ==="
ps | grep -E "(rtkhci|hci)" | grep -v grep
EOF

adb push /tmp/rtkhci_high_baud.sh /tmp/
adb shell "chmod +x /tmp/rtkhci_high_baud.sh && /tmp/rtkhci_high_baud.sh"