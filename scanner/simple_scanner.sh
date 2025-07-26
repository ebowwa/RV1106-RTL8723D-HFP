#!/bin/bash
# Simple scanner that shows what's available

echo "=== RV1106 Simple Device Scanner ==="
echo "Date: $(date)"
echo ""

# Serial devices
echo "[SERIAL DEVICES]"
echo "Available serial ports:"
ls -la /dev/tty* 2>/dev/null | grep -E "(ttyS|ttyUSB|ttyAMA)" | while read line; do
    device=$(echo $line | awk '{print $NF}')
    # Get baud rate if possible
    baud=$(stty -F $device 2>/dev/null | grep -oE "speed [0-9]+" | awk '{print $2}' || echo "unknown")
    echo "  $device (baud: $baud)"
done

echo ""
echo "Serial device details:"
for dev in /dev/ttyS*; do
    if [ -c "$dev" ]; then
        echo "  $dev:"
        stty -F $dev 2>&1 | head -2 | sed 's/^/    /'
    fi
done

# Bluetooth check
echo ""
echo "[BLUETOOTH STATUS]"

# Check if any HCI interface exists
if hciconfig 2>/dev/null | grep -q "hci"; then
    echo "Bluetooth interface found:"
    hciconfig -a 2>/dev/null | head -20
    
    # Try to get some info even if DOWN
    echo ""
    echo "Device features:"
    hciconfig hci0 features 2>/dev/null || echo "  Cannot read features"
    
    echo ""
    echo "Version info:"
    hciconfig hci0 version 2>/dev/null || echo "  Cannot read version"
else
    echo "No Bluetooth HCI interface found"
    
    # Check what's using the UART
    echo ""
    echo "Processes using /dev/ttyS5:"
    lsof /dev/ttyS5 2>/dev/null || fuser -v /dev/ttyS5 2>/dev/null || echo "  Cannot determine"
fi

# System info
echo ""
echo "[SYSTEM INFO]"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime)"
echo ""
echo "Bluetooth-related processes:"
ps | grep -E "(bluetooth|hci|rtk)" | grep -v grep || echo "  None running"

echo ""
echo "Kernel modules:"
lsmod 2>/dev/null | grep -E "(bluetooth|hci|uart|rtl)" || echo "  No Bluetooth modules loaded"

# GPIO status
echo ""
echo "[GPIO STATUS]"
echo "Exported GPIOs:"
ls /sys/class/gpio/ | grep gpio || echo "  None exported"

# Files check
echo ""
echo "[BLUETOOTH FILES]"
echo "Firmware files:"
ls -la /lib/firmware/rtl* 2>/dev/null | head -5 || echo "  No RTL firmware found"

echo ""
echo "Bluetooth binaries:"
which hciconfig hcitool bluetoothd 2>/dev/null || echo "  Standard tools not in PATH"
[ -f /userdata/rtkhci ] && echo "  /userdata/rtkhci exists"
[ -f /tmp/rtk_hciattach ] && echo "  /tmp/rtk_hciattach exists"

echo ""
echo "=== Scan Complete ==="