#!/bin/bash
# Complete oFono build script for GitHub Codespaces
# Run this in a Codespace to build oFono for ARM (RV1106)

set -e  # Exit on error

echo "=== oFono ARM Build Script for RV1106 ==="
echo "This will build oFono to fix HFP issues"
echo ""

# 1. Install dependencies
echo "1. Installing build tools..."
sudo apt-get update
sudo apt-get install -y \
    gcc-arm-linux-gnueabihf \
    g++-arm-linux-gnueabihf \
    libc6-dev-armhf-cross \
    pkg-config \
    autoconf \
    automake \
    libtool \
    git \
    make \
    libdbus-1-dev \
    libglib2.0-dev \
    libbluetooth-dev \
    mobile-broadband-provider-info

# 2. Create build directory
echo -e "\n2. Setting up build environment..."
mkdir -p ~/ofono-build
cd ~/ofono-build

# 3. Clone oFono
echo -e "\n3. Cloning oFono source..."
if [ ! -d "ofono" ]; then
    git clone https://git.kernel.org/pub/scm/network/ofono/ofono.git
fi
cd ofono
git checkout 1.34  # Stable version

# 4. Set up cross-compilation
echo -e "\n4. Configuring for ARM..."
export CC=arm-linux-gnueabihf-gcc
export CXX=arm-linux-gnueabihf-g++
export AR=arm-linux-gnueabihf-ar
export STRIP=arm-linux-gnueabihf-strip
export PKG_CONFIG_PATH=/usr/lib/arm-linux-gnueabihf/pkgconfig
export PKG_CONFIG_LIBDIR=/usr/lib/arm-linux-gnueabihf/pkgconfig

# 5. Bootstrap and configure
echo -e "\n5. Bootstrapping..."
./bootstrap

echo -e "\n6. Configuring..."
./configure \
    --host=arm-linux-gnueabihf \
    --prefix=/usr \
    --sysconfdir=/etc \
    --localstatedir=/var \
    --disable-udev \
    --disable-systemd \
    --enable-bluetooth \
    --enable-tools \
    --disable-dundee \
    --disable-mbim \
    --disable-qmi

# 6. Build
echo -e "\n7. Building oFono..."
make -j$(nproc)

# 7. Create installation package
echo -e "\n8. Creating deployment package..."
make DESTDIR=$PWD/install install
cd install

# Strip binaries to reduce size
find . -type f -executable -exec arm-linux-gnueabihf-strip {} \; 2>/dev/null || true

# Create the package
tar -czf ~/ofono-arm-rv1106.tar.gz *

# 8. Create deployment script
cat > ~/deploy_ofono.sh << 'EOF'
#!/bin/bash
# Deploy oFono to RV1106

if [ ! -f "ofono-arm-rv1106.tar.gz" ]; then
    echo "ERROR: ofono-arm-rv1106.tar.gz not found!"
    exit 1
fi

echo "Deploying oFono to RV1106..."

# Push the package
adb push ofono-arm-rv1106.tar.gz /tmp/

# Extract on device
adb shell << 'DEVICE_EOF'
cd /
tar -xzf /tmp/ofono-arm-rv1106.tar.gz
chmod +x /usr/sbin/ofonod
chmod +x /usr/lib/ofono/test/*

# Create config directory
mkdir -p /etc/ofono

# Create basic configuration
cat > /etc/ofono/main.conf << 'CONFIG_EOF'
[General]
BluetoothDriver=hfp

[Bluetooth]
Enable=true
CONFIG_EOF

echo "oFono deployed successfully!"
echo ""
echo "To start oFono:"
echo "ofonod -n -d"
DEVICE_EOF
EOF

chmod +x ~/deploy_ofono.sh

# 9. Create test script
cat > ~/test_ofono_hfp.sh << 'EOF'
#!/bin/bash
# Test oFono HFP on RV1106

cat > /tmp/test_ofono.sh << 'DEVICE_EOF'
#!/bin/sh
# Test oFono HFP functionality

echo "=== Testing oFono HFP ==="

# 1. Start D-Bus if needed
if [ ! -f /run/dbus/pid ]; then
    dbus-daemon --system &
    sleep 2
fi

# 2. Start bluetoothd
bluetoothd --experimental &
sleep 3

# 3. Start oFono
echo "Starting oFono..."
ofonod -n -d &
OFONO_PID=$!
sleep 5

# 4. Check oFono status
echo -e "\nChecking oFono modems:"
dbus-send --system --print-reply --dest=org.ofono / org.ofono.Manager.GetModems

# 5. Start BlueALSA for A2DP only
echo -e "\nStarting BlueALSA for A2DP..."
bluealsa -p a2dp-sink -p a2dp-source &

echo -e "\n=== HFP Setup Complete ==="
echo "oFono handles HFP (phone calls)"
echo "BlueALSA handles A2DP (music)"
echo ""
echo "To monitor HFP:"
echo "dbus-monitor --system \"type='signal',sender='org.ofono'\""
DEVICE_EOF

adb push /tmp/test_ofono.sh /tmp/
adb shell "chmod +x /tmp/test_ofono.sh && /tmp/test_ofono.sh"
EOF

chmod +x ~/test_ofono_hfp.sh

# 10. Summary
echo -e "\n=== BUILD COMPLETE ==="
echo ""
echo "Files created:"
echo "  ~/ofono-arm-rv1106.tar.gz  - oFono binaries for RV1106"
echo "  ~/deploy_ofono.sh          - Deployment script"
echo "  ~/test_ofono_hfp.sh        - Test script"
echo ""
echo "Next steps:"
echo "1. Download ofono-arm-rv1106.tar.gz from Codespace"
echo "2. Run: ./deploy_ofono.sh"
echo "3. Run: ./test_ofono_hfp.sh"
echo ""
echo "This will fix the HFP 'Too small packet for stream_rej' error!"