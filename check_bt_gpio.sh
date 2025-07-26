#!/bin/bash
# Check Bluetooth GPIO controls

cat > /tmp/check_bt_gpio.sh << 'EOF'
#!/bin/sh
# Check and control Bluetooth GPIO

echo "=== Checking Bluetooth GPIO Controls ==="

# Check BT wake GPIO
echo -e "\nBT Wake GPIO:"
if [ -f /sys/firmware/devicetree/base/wireless-bluetooth/BT,wake_gpio ]; then
    hexdump -C /sys/firmware/devicetree/base/wireless-bluetooth/BT,wake_gpio
fi

# Check UART RTS GPIO
echo -e "\nUART RTS GPIO:"
if [ -f /sys/firmware/devicetree/base/wireless-bluetooth/uart_rts_gpios ]; then
    hexdump -C /sys/firmware/devicetree/base/wireless-bluetooth/uart_rts_gpios
fi

# Look for GPIO exports
echo -e "\nExported GPIOs:"
ls -la /sys/class/gpio/

# Check for Bluetooth reset in /proc/device-tree
echo -e "\nDevice tree BT entries:"
find /proc/device-tree -name "*bluetooth*" -o -name "*bt*" 2>/dev/null | grep -v "btree" | head -20

# Check if there's a reset sequence in the init scripts
echo -e "\nChecking for BT reset in init scripts:"
grep -r "rtl\|RTL\|8723\|bluetooth" /etc/init.d/ 2>/dev/null | head -10
grep -r "rtl\|RTL\|8723\|bluetooth" /etc/rc.d/ 2>/dev/null | head -10

# Try GPIO manipulation if we find BT GPIO
echo -e "\nTrying to reset BT via GPIO..."
# Common GPIO numbers for BT enable on Rockchip boards
for gpio in 139 140 141 142; do
    if [ ! -d /sys/class/gpio/gpio$gpio ]; then
        echo $gpio > /sys/class/gpio/export 2>/dev/null
    fi
    
    if [ -d /sys/class/gpio/gpio$gpio ]; then
        echo "Found GPIO $gpio"
        echo out > /sys/class/gpio/gpio$gpio/direction 2>/dev/null
        # Reset cycle
        echo 0 > /sys/class/gpio/gpio$gpio/value 2>/dev/null
        sleep 0.5
        echo 1 > /sys/class/gpio/gpio$gpio/value 2>/dev/null
        echo "Toggled GPIO $gpio"
    fi
done

echo -e "\nDone checking GPIOs"
EOF

adb push /tmp/check_bt_gpio.sh /tmp/
adb shell "chmod +x /tmp/check_bt_gpio.sh && /tmp/check_bt_gpio.sh"