#!/bin/bash
# Device Scanner Shell Script for RV1106
# Scans serial ports and Bluetooth devices

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== RV1106 Device Scanner ===${NC}"
echo "Scanning for Serial and Bluetooth devices..."

# Function to scan serial devices
scan_serial() {
    echo -e "\n${GREEN}[Serial/UART Devices]${NC}"
    
    # List all tty devices
    echo "TTY Devices:"
    ls -la /dev/tty* 2>/dev/null | grep -E "(ttyS|ttyUSB|ttyAMA|ttyACM)" | while read line; do
        device=$(echo $line | awk '{print $NF}')
        echo -n "  $device"
        
        # Try to get baud rate
        if stty -F $device 2>/dev/null | grep -q "speed"; then
            baud=$(stty -F $device 2>/dev/null | grep -oE "speed [0-9]+" | awk '{print $2}')
            echo " (${baud} baud)"
        else
            echo ""
        fi
    done
    
    # Check USB serial devices
    if command -v lsusb >/dev/null 2>&1; then
        echo -e "\nUSB Serial Devices:"
        lsusb | grep -iE "(serial|uart|ftdi|pl2303|ch340)" || echo "  None found"
    fi
    
    # Check device tree for UART configurations
    echo -e "\nDevice Tree UART Configurations:"
    if [ -d /sys/firmware/devicetree/base ]; then
        find /sys/firmware/devicetree/base -name "*uart*" -o -name "*serial*" 2>/dev/null | head -10
    fi
}

# Function to scan Bluetooth Classic
scan_bt_classic() {
    echo -e "\n${GREEN}[Bluetooth Classic Devices]${NC}"
    
    # Check HCI interface
    if ! hciconfig hci0 >/dev/null 2>&1; then
        echo "No HCI interface found. Attempting initialization..."
        
        # Try to initialize
        if [ -f /tmp/rtk_hciattach ]; then
            /tmp/rtk_hciattach -s 115200 /dev/ttyS5 rtk_h5 &
            sleep 5
        elif [ -f /userdata/rtkhci ]; then
            /userdata/rtkhci -n -s 115200 /dev/ttyS5 rtk_h5 &
            sleep 5
        else
            hciattach /dev/ttyS5 any 1500000 flow &
            sleep 5
        fi
        
        hciconfig hci0 up 2>/dev/null
    fi
    
    # Show HCI info
    echo "HCI Interface Status:"
    hciconfig -a | head -10
    
    # Scan for devices
    echo -e "\nScanning for Classic devices (10 seconds)..."
    timeout 10 hcitool scan 2>/dev/null || echo "Scan failed or no devices found"
}

# Function to scan BLE devices
scan_bt_le() {
    echo -e "\n${GREEN}[Bluetooth Low Energy Devices]${NC}"
    
    # Check if LE is supported
    if hciconfig hci0 lestates >/dev/null 2>&1; then
        echo "BLE is supported"
        
        # Enable LE advertising
        hciconfig hci0 leadv >/dev/null 2>&1
        
        # Scan for LE devices
        echo "Scanning for BLE devices (10 seconds)..."
        timeout 10 hcitool lescan 2>/dev/null || echo "LE scan failed or no devices found"
    else
        echo "BLE not supported or not initialized"
    fi
}

# Function to show system info
show_system_info() {
    echo -e "\n${GREEN}[System Information]${NC}"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    
    # Check for Bluetooth modules
    echo -e "\nLoaded Bluetooth modules:"
    lsmod | grep -E "(bluetooth|btusb|btrtl|hci_uart)" || echo "  No Bluetooth modules loaded"
    
    # Check for rfkill status
    if command -v rfkill >/dev/null 2>&1; then
        echo -e "\nRFKill status:"
        rfkill list bluetooth 2>/dev/null || echo "  No Bluetooth rfkill entries"
    fi
}

# Main execution
case "${1:-all}" in
    serial)
        scan_serial
        ;;
    classic)
        scan_bt_classic
        ;;
    ble|le)
        scan_bt_le
        ;;
    info)
        show_system_info
        ;;
    all|*)
        scan_serial
        scan_bt_classic
        scan_bt_le
        show_system_info
        ;;
esac

echo -e "\n${BLUE}Scan complete!${NC}"