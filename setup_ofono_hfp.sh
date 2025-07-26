#!/bin/bash
# Set up oFono for proper HFP support on RV1106

cat > /tmp/setup_ofono.sh << 'EOF'
#!/bin/sh
# Complete oFono + BlueALSA setup for HFP support

echo "=== Setting up oFono for HFP Support ==="
echo "oFono provides proper HFP-HF (client) implementation"

# 1. Check if oFono is installed
echo "1. Checking for oFono..."
if ! which ofonod 2>/dev/null; then
    echo "oFono not found. Installing..."
    # Try different package managers
    if which opkg 2>/dev/null; then
        opkg update
        opkg install ofono
    elif which apt-get 2>/dev/null; then
        apt-get update
        apt-get install -y ofono
    else
        echo "ERROR: No package manager found to install oFono"
        echo "Please install oFono manually"
        exit 1
    fi
fi

# 2. Clean up existing services
echo -e "\n2. Cleaning up existing services..."
killall -q ofonod bluealsa bluetoothd 2>/dev/null
sleep 2

# 3. Configure oFono for HFP
echo -e "\n3. Configuring oFono..."
mkdir -p /etc/ofono

# Create oFono configuration
cat > /etc/ofono/phonesim.conf << 'OFONO_EOF'
[phonesim]
Driver=phonesim
Address=127.0.0.1
Port=12345
OFONO_EOF

# 4. Start D-Bus if needed
echo -e "\n4. Starting D-Bus..."
if [ ! -f /run/dbus/pid ]; then
    rm -f /run/messagebus.pid 2>/dev/null
    dbus-daemon --system &
    sleep 2
fi

# 5. Start BlueZ with HFP support
echo -e "\n5. Starting BlueZ..."
if [ -f /usr/libexec/bluetooth/bluetoothd ]; then
    # Start with experimental flag for full HFP support
    bluetoothd --experimental -d &
    sleep 3
else
    echo "WARNING: bluetoothd not found"
fi

# 6. Start oFono
echo -e "\n6. Starting oFono..."
ofonod -n -d &
OFONO_PID=$!
sleep 3

# 7. Configure oFono HFP
echo -e "\n7. Configuring oFono HFP..."
# Enable Bluetooth HFP in oFono
dbus-send --system --print-reply --dest=org.ofono / org.ofono.Manager.GetModems 2>/dev/null || echo "oFono starting..."

# 8. Start BlueALSA for A2DP only
echo -e "\n8. Starting BlueALSA for A2DP..."
# Only use A2DP profiles, let oFono handle HFP
bluealsa -p a2dp-source -p a2dp-sink &
BLUEALSA_PID=$!
sleep 2

# 9. Start audio playback
bluealsa-aplay 00:00:00:00:00:00 &

echo -e "\n=== oFono + BlueALSA Setup Complete ==="
echo ""
echo "Configuration:"
echo "- oFono: Handles HFP (phone calls)"
echo "- BlueALSA: Handles A2DP (music streaming)"
echo "- BlueZ: Manages Bluetooth connections"
echo ""
echo "To test HFP:"
echo "1. Pair your phone using bluetoothctl"
echo "2. Make a phone call"
echo "3. Audio should route through HFP via oFono"
echo ""
echo "Monitor oFono:"
echo "dbus-monitor --system \"type='signal',interface='org.ofono.Modem'\""
echo ""
echo "Check oFono status:"
echo "dbus-send --system --print-reply --dest=org.ofono / org.ofono.Manager.GetModems"

# Show running processes
echo -e "\n=== Running Processes ==="
ps | grep -E "(ofono|bluealsa|bluetoothd)" | grep -v grep

# Create HFP test script
cat > /tmp/test_hfp_ofono.sh << 'TEST_EOF'
#!/bin/sh
# Test HFP with oFono

echo "=== Testing HFP with oFono ==="

# List oFono modems
echo -e "\nListing oFono modems:"
dbus-send --system --print-reply --dest=org.ofono / org.ofono.Manager.GetModems

# Check HFP gateway
echo -e "\nChecking HFP gateway:"
dbus-send --system --print-reply --dest=org.bluez /org/bluez org.freedesktop.DBus.ObjectManager.GetManagedObjects | grep -A5 "HandsfreeGateway"

echo -e "\nTo monitor HFP calls:"
echo "dbus-monitor --system \"type='signal',sender='org.ofono'\""
TEST_EOF

chmod +x /tmp/test_hfp_ofono.sh
echo -e "\n=== Created test script: /tmp/test_hfp_ofono.sh ==="

EOF

# Deploy and run
adb push /tmp/setup_ofono.sh /tmp/
adb shell "chmod +x /tmp/setup_ofono.sh && /tmp/setup_ofono.sh"