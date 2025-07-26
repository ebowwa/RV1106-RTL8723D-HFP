#!/bin/bash
# Use the exact rtkhci binary from the PDF

cat > /tmp/rtkhci_exact.sh << 'EOF'
#!/bin/sh
# Use rtkhci exactly as shown in the PDF

echo "=== Using rtkhci from PDF ==="
echo "This is what they had working for A2DP"

# Clean up first
killall -q rtkhci rtk_hciattach hciattach 2>/dev/null
sleep 2

# Reset UART to clean state
stty -F /dev/ttyS5 sane 2>/dev/null
stty -F /dev/ttyS5 115200 cs8 -cstopb -parenb 2>/dev/null

# Use rtkhci exactly as shown in PDF
echo "Running: /userdata/rtkhci -n -s 115200 /dev/ttyS5 rtk_h5"
cd /userdata
./rtkhci -n -s 115200 /dev/ttyS5 rtk_h5 &
RTKHCI_PID=$!

echo "rtkhci started with PID: $RTKHCI_PID"

# Wait for initialization
echo "Waiting for initialization..."
sleep 10

# Check if still running
if kill -0 $RTKHCI_PID 2>/dev/null; then
    echo "rtkhci is still running"
else
    echo "rtkhci exited"
fi

# Check HCI interface
echo -e "\nChecking HCI interface:"
hciconfig -a

# Try to bring up
echo -e "\nBringing up interface:"
hciconfig hci0 up

# Configure
echo -e "\nConfiguring:"
hciconfig hci0 piscan
hciconfig hci0 name 'Memo-i'

# Final status
echo -e "\n=== Final Status ==="
hciconfig hci0
ps | grep rtkhci | grep -v grep
EOF

adb push /tmp/rtkhci_exact.sh /tmp/
adb shell "chmod +x /tmp/rtkhci_exact.sh && /tmp/rtkhci_exact.sh"