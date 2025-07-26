#!/bin/bash
# Install and run RTL8723D Bluetooth fix

echo "Installing RTL8723D Bluetooth support..."

# Download rtk_hciattach ARM binary
echo "Downloading rtk_hciattach for ARM..."
curl -L https://github.com/lwfinger/rtl8723bs_bt/releases/download/v1.0/rtk_hciattach_arm -o rtk_hciattach_arm 2>/dev/null

if [ ! -f rtk_hciattach_arm ]; then
    echo "Download failed. Building from source..."
    
    # Alternative: Use Docker to cross-compile
    if command -v docker &> /dev/null; then
        echo "Using Docker to cross-compile..."
        
        cat > Dockerfile.arm << 'EOF'
FROM arm32v7/debian:buster
RUN apt-get update && apt-get install -y gcc make
WORKDIR /build
COPY *.c *.h Makefile ./
RUN make rtk_hciattach
EOF
        
        docker build -t rtk_build -f Dockerfile.arm .
        docker run --rm -v $(pwd):/out rtk_build cp rtk_hciattach /out/rtk_hciattach_arm
    fi
fi

if [ -f rtk_hciattach_arm ]; then
    echo "Deploying to device..."
    adb push rtk_hciattach_arm /tmp/rtk_hciattach
    adb shell "chmod +x /tmp/rtk_hciattach"
    
    echo "Running rtk_hciattach..."
    adb shell "/tmp/rtk_hciattach -n -s 115200 /dev/ttyS5 rtk_h5"
else
    echo "Could not get rtk_hciattach. Using fallback method..."
    
    # Fallback: Direct firmware load attempt
    adb shell << 'FALLBACK'
#!/bin/sh
echo "Fallback: Manual RTL8723D initialization"

# Kill existing
killall hciattach btattach 2>/dev/null

# Setup firmware paths
mkdir -p /lib/firmware/rtl_bt
ln -sf /lib/firmware/rtlbt/rtl8723d_fw /lib/firmware/rtl_bt/rtlbt_fw
ln -sf /lib/firmware/rtlbt/rtl8723d_config /lib/firmware/rtl_bt/rtlbt_config

# Try with different protocols
for PROTO in rtk_h5 h5 h4; do
    echo "Trying protocol: $PROTO"
    hciattach -n -s 115200 /dev/ttyS5 $PROTO &
    PID=$!
    sleep 3
    
    if hciconfig hci0 2>/dev/null | grep -q "BD Address"; then
        MAC=$(hciconfig hci0 | grep "BD Address" | awk '{print $3}')
        if [ "$MAC" != "00:00:00:00:00:00" ]; then
            echo "Success! MAC: $MAC"
            hciconfig hci0 up
            hciconfig -a
            exit 0
        fi
    fi
    
    kill $PID 2>/dev/null
done

echo "All attempts failed. The device needs rtk_hciattach tool."
FALLBACK
fi