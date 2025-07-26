#!/bin/bash
# RV1106 Bluetooth Manager - Complete solution for RTL8723D HFP
# Handles everything from firmware extraction to deployment

set -e  # Exit on error

# Configuration
DEVICE_IP="rv1106"  # Change to actual IP if needed
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRMWARE_DIR="${PROJECT_DIR}/rtl8723d_firmware"
BUILD_DIR="${PROJECT_DIR}/build"
DEVICE_DIR="/opt/bluetooth"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_device() {
    log_info "Checking device connection..."
    if adb devices | grep -q "device$"; then
        DEVICE_ID=$(adb devices | grep device$ | awk '{print $1}')
        log_info "Found device: $DEVICE_ID"
        return 0
    else
        log_error "No device found. Please connect RV1106 via USB"
        return 1
    fi
}

extract_firmware() {
    log_info "Extracting firmware from device..."
    
    mkdir -p "$FIRMWARE_DIR"
    
    # Pull firmware files
    adb pull /lib/firmware/rtlbt/rtl8723d_fw "$FIRMWARE_DIR/" 2>/dev/null || {
        log_warn "Firmware not found at /lib/firmware/rtlbt/"
        log_info "Searching for firmware..."
        
        # Search for firmware
        FW_PATH=$(adb shell "find /lib /vendor -name 'rtl8723d*' 2>/dev/null | head -1")
        
        if [ -n "$FW_PATH" ]; then
            adb pull "$FW_PATH" "$FIRMWARE_DIR/"
        else
            log_error "RTL8723D firmware not found on device"
            return 1
        fi
    }
    
    adb pull /lib/firmware/rtlbt/rtl8723d_config "$FIRMWARE_DIR/" 2>/dev/null || {
        log_warn "Config file not found"
    }
    
    log_info "Firmware extracted to $FIRMWARE_DIR"
    ls -la "$FIRMWARE_DIR"
}

build_tools() {
    log_info "Building native tools..."
    
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # Check for cross-compiler
    if ! command -v arm-linux-gnueabihf-gcc &> /dev/null; then
        log_warn "Cross-compiler not found. Attempting to build on device..."
        BUILD_ON_DEVICE=1
    else
        BUILD_ON_DEVICE=0
    fi
    
    if [ "$BUILD_ON_DEVICE" -eq 0 ]; then
        # Cross-compile
        log_info "Cross-compiling for ARM..."
        
        # Copy source files
        cp -r "$PROJECT_DIR/device_code"/* "$BUILD_DIR/"
        
        # Build
        make CROSS_COMPILE=arm-linux-gnueabihf- all
        
        log_info "Build complete. Binaries:"
        ls -la rtk_hciattach hfp_monitor 2>/dev/null || true
    else
        # Build on device
        log_info "Building on device..."
        
        # Copy sources to device
        adb shell "mkdir -p /tmp/build"
        adb push "$PROJECT_DIR/device_code"/* /tmp/build/
        
        # Build on device
        adb shell "cd /tmp/build && gcc -O2 -o rtk_hciattach rtk_hciattach.c"
        adb shell "cd /tmp/build && gcc -O2 -o hfp_monitor hfp_monitor.c -lbluetooth"
        
        # Pull binaries back
        adb pull /tmp/build/rtk_hciattach "$BUILD_DIR/"
        adb pull /tmp/build/hfp_monitor "$BUILD_DIR/"
    fi
}

deploy_to_device() {
    log_info "Deploying to device..."
    
    # Create directory structure on device
    adb shell "mkdir -p $DEVICE_DIR/{bin,firmware,scripts,config}"
    
    # Deploy binaries
    if [ -f "$BUILD_DIR/rtk_hciattach" ]; then
        adb push "$BUILD_DIR/rtk_hciattach" "$DEVICE_DIR/bin/"
        adb shell "chmod +x $DEVICE_DIR/bin/rtk_hciattach"
    fi
    
    if [ -f "$BUILD_DIR/hfp_monitor" ]; then
        adb push "$BUILD_DIR/hfp_monitor" "$DEVICE_DIR/bin/"
        adb shell "chmod +x $DEVICE_DIR/bin/hfp_monitor"
    fi
    
    # Deploy firmware
    adb push "$FIRMWARE_DIR"/* "$DEVICE_DIR/firmware/" 2>/dev/null || true
    
    # Create startup script
    cat > /tmp/bluetooth_start.sh << 'EOF'
#!/bin/sh
# RTL8723D Bluetooth Startup Script

DEVICE_DIR="/opt/bluetooth"
LOG="/var/log/bluetooth_init.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG
}

# Kill any existing processes
killall rtk_hciattach hfp_monitor bluealsa 2>/dev/null

# GPIO initialization (adjust pins as needed)
init_gpio() {
    # Example GPIO setup - adjust for your board
    if [ -d /sys/class/gpio ]; then
        # BT_REG_ON
        echo 110 > /sys/class/gpio/export 2>/dev/null
        echo out > /sys/class/gpio/gpio110/direction
        echo 0 > /sys/class/gpio/gpio110/value
        sleep 0.1
        echo 1 > /sys/class/gpio/gpio110/value
        log "GPIO initialized"
    fi
}

# Initialize Bluetooth
init_bluetooth() {
    log "Initializing RTL8723D..."
    
    # Try rtk_hciattach first
    if [ -x "$DEVICE_DIR/bin/rtk_hciattach" ]; then
        $DEVICE_DIR/bin/rtk_hciattach -n -s 115200 /dev/ttyS5 rtk_h5 &
        RTK_PID=$!
        sleep 3
        
        if hciconfig hci0 2>/dev/null; then
            log "HCI interface created successfully"
            return 0
        else
            kill $RTK_PID 2>/dev/null
        fi
    fi
    
    # Fallback to standard hciattach
    log "Trying standard hciattach..."
    hciattach /dev/ttyS5 any 1500000 flow
    sleep 2
    
    if hciconfig hci0 2>/dev/null; then
        log "HCI interface created with standard hciattach"
        return 0
    fi
    
    log "Failed to initialize Bluetooth"
    return 1
}

# Configure HCI
configure_hci() {
    log "Configuring HCI..."
    
    hciconfig hci0 up
    hciconfig hci0 piscan
    hciconfig hci0 sspmode 1
    hciconfig hci0 name "RV1106-RTL8723D"
    
    # Set SCO MTU for better compatibility
    hciconfig hci0 scomtu 64:8
    
    log "HCI configured"
}

# Start BlueALSA
start_bluealsa() {
    log "Starting BlueALSA..."
    
    bluealsa -p hfp-hf -p a2dp-sink \
        --hfp-codec=cvsd \
        --io-thread-rt-priority=99 \
        -B /var/run/bluealsa &
    
    BLUEALSA_PID=$!
    sleep 2
    
    if kill -0 $BLUEALSA_PID 2>/dev/null; then
        log "BlueALSA started (PID: $BLUEALSA_PID)"
        return 0
    else
        log "BlueALSA failed to start"
        return 1
    fi
}

# Start monitor
start_monitor() {
    if [ -x "$DEVICE_DIR/bin/hfp_monitor" ]; then
        log "Starting HFP monitor..."
        $DEVICE_DIR/bin/hfp_monitor -d
    fi
}

# Main execution
main() {
    log "=== Starting Bluetooth initialization ==="
    
    init_gpio
    
    if init_bluetooth; then
        configure_hci
        start_bluealsa
        start_monitor
        log "=== Bluetooth initialization complete ==="
    else
        log "=== Bluetooth initialization failed ==="
        exit 1
    fi
}

main
EOF

    adb push /tmp/bluetooth_start.sh "$DEVICE_DIR/scripts/"
    adb shell "chmod +x $DEVICE_DIR/scripts/bluetooth_start.sh"
    
    # Create systemd service
    cat > /tmp/bluetooth-rtl8723d.service << EOF
[Unit]
Description=RTL8723D Bluetooth Service
After=sys-subsystem-bluetooth-devices-hci0.device

[Service]
Type=forking
ExecStart=$DEVICE_DIR/scripts/bluetooth_start.sh
ExecStop=/usr/bin/killall rtk_hciattach hfp_monitor bluealsa
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    adb push /tmp/bluetooth-rtl8723d.service /tmp/
    adb shell "cp /tmp/bluetooth-rtl8723d.service /etc/systemd/system/ 2>/dev/null || \
               cp /tmp/bluetooth-rtl8723d.service /etc/init.d/bluetooth-rtl8723d"
    
    log_info "Deployment complete"
}

test_bluetooth() {
    log_info "Testing Bluetooth functionality..."
    
    # Start Bluetooth
    adb shell "$DEVICE_DIR/scripts/bluetooth_start.sh"
    sleep 5
    
    # Check HCI
    log_info "HCI Status:"
    adb shell "hciconfig -a"
    
    # Scan for devices
    log_info "Scanning for devices..."
    adb shell "timeout 10 hcitool scan"
    
    # Check BlueALSA
    log_info "BlueALSA Status:"
    adb shell "ps -ef | grep bluealsa"
    adb shell "bluealsa-aplay -L 2>/dev/null || echo 'bluealsa-aplay not found'"
}

monitor_live() {
    log_info "Starting live monitoring..."
    
    # Create monitoring script
    cat > /tmp/live_monitor.sh << 'EOF'
#!/bin/bash

clear
while true; do
    echo -e "\033[H\033[J"  # Clear screen
    echo "=== RV1106 Bluetooth Monitor ==="
    echo "Time: $(date)"
    echo ""
    
    # HCI Status
    echo "HCI Status:"
    hciconfig hci0 2>/dev/null || echo "  No HCI interface"
    echo ""
    
    # Connections
    echo "Active Connections:"
    hcitool con 2>/dev/null || echo "  No connections"
    echo ""
    
    # BlueALSA
    echo "BlueALSA:"
    if pidof bluealsa > /dev/null; then
        echo "  Running (PID: $(pidof bluealsa))"
        bluealsa-aplay -L 2>/dev/null | head -5 || true
    else
        echo "  Not running"
    fi
    echo ""
    
    # System resources
    echo "System Resources:"
    adb shell "top -n 1 | grep -E 'bluealsa|hciattach|bluetoothd' | head -5"
    
    echo ""
    echo "Press Ctrl+C to exit"
    
    sleep 2
done
EOF

    # Run monitor
    bash /tmp/live_monitor.sh
}

fix_common_issues() {
    log_info "Attempting to fix common issues..."
    
    # Issue 1: No HCI interface
    if ! adb shell "hciconfig hci0" &>/dev/null; then
        log_warn "No HCI interface found"
        
        # Try different baud rates
        for BAUD in 1500000 921600 460800 230400 115200; do
            log_info "Trying baud rate: $BAUD"
            adb shell "killall hciattach 2>/dev/null"
            adb shell "hciattach /dev/ttyS5 any $BAUD flow noflow"
            sleep 2
            
            if adb shell "hciconfig hci0" &>/dev/null; then
                log_info "Success at $BAUD baud!"
                break
            fi
        done
    fi
    
    # Issue 2: MAC address 00:00:00:00:00:00
    MAC=$(adb shell "hciconfig hci0 | grep BD | awk '{print \$3}'" 2>/dev/null)
    if [ "$MAC" = "00:00:00:00:00:00" ]; then
        log_warn "Invalid MAC address, firmware not loaded"
        
        # Try loading firmware manually
        log_info "Attempting manual firmware load..."
        adb shell "$DEVICE_DIR/scripts/bluetooth_start.sh"
    fi
    
    # Issue 3: BlueALSA not finding devices
    if ! adb shell "bluealsa-aplay -L 2>&1" | grep -q "bluealsa:"; then
        log_warn "BlueALSA not working properly"
        
        # Restart BlueALSA
        adb shell "killall bluealsa 2>/dev/null"
        adb shell "bluealsa -p hfp-hf --hfp-codec=cvsd &"
    fi
}

# Main menu
show_menu() {
    echo ""
    echo "RV1106 Bluetooth Manager"
    echo "========================"
    echo "1) Check device connection"
    echo "2) Extract firmware from device"
    echo "3) Build tools"
    echo "4) Deploy to device"
    echo "5) Test Bluetooth"
    echo "6) Monitor live"
    echo "7) Fix common issues"
    echo "8) Full setup (all steps)"
    echo "9) Quick start (deploy and test)"
    echo "0) Exit"
    echo ""
}

# Quick functions for common tasks
quick_start() {
    check_device && \
    deploy_to_device && \
    test_bluetooth
}

full_setup() {
    check_device && \
    extract_firmware && \
    build_tools && \
    deploy_to_device && \
    test_bluetooth
}

# Main loop
main() {
    while true; do
        show_menu
        read -p "Select option: " choice
        
        case $choice in
            1) check_device ;;
            2) extract_firmware ;;
            3) build_tools ;;
            4) deploy_to_device ;;
            5) test_bluetooth ;;
            6) monitor_live ;;
            7) fix_common_issues ;;
            8) full_setup ;;
            9) quick_start ;;
            0) exit 0 ;;
            *) log_error "Invalid option" ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Handle script arguments
case "${1:-}" in
    --check)
        check_device
        ;;
    --extract)
        extract_firmware
        ;;
    --build)
        build_tools
        ;;
    --deploy)
        deploy_to_device
        ;;
    --test)
        test_bluetooth
        ;;
    --monitor)
        monitor_live
        ;;
    --fix)
        fix_common_issues
        ;;
    --quick)
        quick_start
        ;;
    --full)
        full_setup
        ;;
    --help|-h)
        echo "Usage: $0 [option]"
        echo ""
        echo "Options:"
        echo "  --check    Check device connection"
        echo "  --extract  Extract firmware from device"
        echo "  --build    Build native tools"
        echo "  --deploy   Deploy to device"
        echo "  --test     Test Bluetooth functionality"
        echo "  --monitor  Start live monitoring"
        echo "  --fix      Fix common issues"
        echo "  --quick    Quick start (deploy and test)"
        echo "  --full     Full setup (all steps)"
        echo "  --help     Show this help"
        echo ""
        echo "Without options, shows interactive menu"
        ;;
    *)
        main
        ;;
esac