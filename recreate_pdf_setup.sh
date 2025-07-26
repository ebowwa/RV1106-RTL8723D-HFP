#!/bin/bash
# Recreate the exact setup from the PDF that was working

cat > /tmp/pdf_exact_setup.sh << 'EOF'
#!/bin/sh
# Exact setup from PDF that showed A2DP working (page 10-11)

echo "=== Recreating PDF Setup ==="
echo "Following the exact sequence that worked for A2DP"

# 1. Clean start
killall -q dbus-daemon bluetoothd rtkhci bluealsa bluealsa-aplay 2>/dev/null
rm -f /run/messagebus.pid

# 2. Start dbus-daemon (they had this working)
echo "Starting dbus-daemon..."
dbus-daemon --system --print-pid --print-address &
sleep 1

# 3. Initialize RTL8723D with rtkhci (they used rtkhci, not rtk_hciattach!)
echo "Initializing RTL8723D firmware..."
cd /userdata
if [ -f ./rtkhci ]; then
    chmod +x ./rtkhci
    ./rtkhci -n -s 115200 /dev/ttyS5 rtk_h5 &
    RTKHCI_PID=$!
    echo "Started rtkhci with PID: $RTKHCI_PID"
else
    # Use our rtk_hciattach as fallback
    echo "rtkhci not found, using rtk_hciattach..."
    /tmp/rtk_hciattach -n -s 115200 /dev/ttyS5 rtk_h5 &
    RTKHCI_PID=$!
fi

# Wait for full initialization (they showed it working after this)
sleep 10

# 4. Bring up Bluetooth interface (exact sequence from PDF)
echo "Bringing up Bluetooth interface..."
rfkill unblock bluetooth
hciconfig hci0 up
sleep 1
hciconfig hci0 piscan
sleep 3
hciconfig hci0 name 'Memo-i'
sleep 1
hciconfig hci0 down
sleep 1
hciconfig hci0 up
sleep 1
hciconfig hci0 piscan
sleep 3

# 5. Start bluetoothd with experimental flag (required for HFP HF)
echo "Starting bluetoothd with experimental flag..."
/usr/libexec/bluetooth/bluetoothd --experimental --compat -n -d &
BLUETOOTHD_PID=$!
sleep 3

# 6. Add SDP records
echo "Adding SDP records..."
sdptool add HF
sdptool add A2SNK

# 7. Start BlueALSA with HFP profile (they tried multiple variations)
echo "Starting BlueALSA with HFP support..."
# Their working command for A2DP:
bluealsa --profile=a2dp-sink &
sleep 2

# For HFP, they tried:
# bluealsa -p a2dp-sink -p hfp-hf --hfp-msc --dbus=org.bluealsa &

# 8. Set audio class
hciconfig hci0 class 0x240404

echo -e "\n=== Setup Complete ==="
echo "From the PDF, A2DP was working at this point"
echo "The phone connected and played YouTube audio successfully"
echo ""
echo "Key differences from our attempts:"
echo "1. They used 'rtkhci' not 'rtk_hciattach'"
echo "2. They used --experimental flag on bluetoothd"
echo "3. They added SDP records with sdptool"
echo "4. For HFP, they saw: 'Too small packet for stream_rej' errors"
echo ""
echo "Current status:"
hciconfig -a
ps | grep -E "(rtk|bluetooth|bluealsa)" | grep -v grep

echo -e "\n=== To connect phone (from PDF) ==="
echo "bluetoothctl"
echo "  power on"
echo "  agent on"  
echo "  default-agent"
echo "  scan on"
echo "  discoverable on"
echo "  pairable on"
echo ""
echo "Then on phone: pair and connect"
echo "For HFP test: make a phone call"
EOF

# Deploy and run
adb push /tmp/pdf_exact_setup.sh /tmp/
adb shell "chmod +x /tmp/pdf_exact_setup.sh && /tmp/pdf_exact_setup.sh"