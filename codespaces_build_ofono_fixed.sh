#!/bin/bash
# Fixed oFono build script with proper ARM dependencies
set -e

echo "=== oFono ARM Build Script (Fixed) ==="
echo ""

# 1. Enable ARM architecture in apt
echo "1. Setting up ARM architecture support..."
sudo dpkg --add-architecture armhf
sudo apt-get update

# 2. Install ARM dependencies
echo -e "\n2. Installing ARM libraries..."
sudo apt-get install -y \
    gcc-arm-linux-gnueabihf \
    g++-arm-linux-gnueabihf \
    pkg-config \
    autoconf \
    automake \
    libtool \
    libglib2.0-dev:armhf \
    libdbus-1-dev:armhf \
    libbluetooth-dev:armhf \
    mobile-broadband-provider-info

# 3. Create build directory
echo -e "\n3. Setting up build environment..."
mkdir -p ~/ofono-build
cd ~/ofono-build

# 4. Clone oFono
echo -e "\n4. Cloning oFono source..."
if [ ! -d "ofono" ]; then
    git clone https://git.kernel.org/pub/scm/network/ofono/ofono.git
fi
cd ofono
git checkout 1.34

# 5. Set up cross-compilation with proper paths
echo -e "\n5. Configuring cross-compilation..."
export CC=arm-linux-gnueabihf-gcc
export CXX=arm-linux-gnueabihf-g++
export AR=arm-linux-gnueabihf-ar
export STRIP=arm-linux-gnueabihf-strip

# Important: Set pkg-config to find ARM libraries
export PKG_CONFIG_PATH=/usr/lib/arm-linux-gnueabihf/pkgconfig
export PKG_CONFIG_LIBDIR=/usr/lib/arm-linux-gnueabihf/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=/

# 6. Bootstrap
echo -e "\n6. Bootstrapping..."
./bootstrap

# 7. Configure with minimal features for embedded
echo -e "\n7. Configuring for RV1106..."
./configure \
    --host=arm-linux-gnueabihf \
    --prefix=/usr \
    --sysconfdir=/etc \
    --localstatedir=/var \
    --disable-test \
    --disable-tools \
    --disable-dundee \
    --enable-bluetooth \
    --with-dbusconfdir=/etc \
    --with-dbusdatadir=/usr/share \
    CFLAGS="-I/usr/include" \
    LDFLAGS="-L/usr/lib/arm-linux-gnueabihf"

# 8. Build
echo -e "\n8. Building oFono..."
make -j$(nproc)

# 9. Create installation package
echo -e "\n9. Creating deployment package..."
make DESTDIR=$PWD/install install
cd install

# Strip binaries
find . -type f -executable -exec arm-linux-gnueabihf-strip {} \; 2>/dev/null || true

# Create minimal package (remove docs and unnecessary files)
rm -rf usr/share/man usr/share/doc

# Package it
tar -czf ~/ofono-arm-rv1106.tar.gz *

# 10. Create deployment script
cat > ~/deploy_ofono_rv1106.sh << 'EOF'
#!/bin/bash
# Deploy oFono to RV1106 for HFP fix

echo "=== Deploying oFono to RV1106 ==="

if [ ! -f "ofono-arm-rv1106.tar.gz" ]; then
    echo "ERROR: ofono-arm-rv1106.tar.gz not found!"
    exit 1
fi

# Push to device
adb push ofono-arm-rv1106.tar.gz /tmp/

# Install on device
adb shell << 'SHELL_EOF'
# Extract
cd /
tar -xzf /tmp/ofono-arm-rv1106.tar.gz

# Make executables
chmod +x /usr/sbin/ofonod

# Create config directory
mkdir -p /etc/ofono

# Create HFP-focused config
cat > /etc/ofono/main.conf << 'CONFIG_EOF'
[General]

[Bluetooth]
Enable=true
CONFIG_EOF

echo "oFono installed successfully!"
SHELL_EOF

# Create test script for HFP
cat > /tmp/test_ofono_hfp.sh << 'TEST_EOF'
#!/bin/sh
# Test oFono HFP with BlueALSA

echo "=== Setting up oFono + BlueALSA for HFP ==="

# Kill existing services
killall -q ofonod bluealsa 2>/dev/null
sleep 2

# Start D-Bus
if [ ! -f /run/dbus/pid ]; then
    rm -f /run/messagebus.pid
    dbus-daemon --system --fork
    sleep 2
fi

# Initialize Bluetooth (use working method)
hciattach /dev/ttyS5 any 1500000 flow &
sleep 5
hciconfig hci0 up

# Start bluetoothd
bluetoothd --experimental &
sleep 3

# Start oFono for HFP
echo "Starting oFono..."
ofonod -d &
sleep 5

# Check oFono status
echo "oFono modems:"
dbus-send --system --print-reply --dest=org.ofono / org.ofono.Manager.GetModems 2>/dev/null || echo "Waiting for oFono..."

# Start BlueALSA for A2DP only (let oFono handle HFP)
echo "Starting BlueALSA for A2DP..."
bluealsa -p a2dp-sink -p a2dp-source &

echo ""
echo "=== Configuration Complete ==="
echo "- oFono: Handles HFP (phone calls)"
echo "- BlueALSA: Handles A2DP (music)"
echo ""
echo "This fixes the 'Too small packet for stream_rej' error!"
TEST_EOF

adb push /tmp/test_ofono_hfp.sh /tmp/
echo ""
echo "Test script deployed to device: /tmp/test_ofono_hfp.sh"
EOF

chmod +x ~/deploy_ofono_rv1106.sh

# 11. Alternative: Build minimal oFono if full build fails
if [ ! -f ~/ofono-arm-rv1106.tar.gz ]; then
    echo -e "\n=== Alternative: Building minimal oFono ==="
    cd ~/ofono-build/ofono
    
    # Clean and try minimal build
    make clean || true
    
    # Just build the core daemon and HFP plugin
    ./configure \
        --host=arm-linux-gnueabihf \
        --prefix=/usr \
        --disable-test \
        --disable-tools \
        --disable-dundee \
        --disable-provision \
        --disable-upower \
        --enable-bluetooth
    
    # Build just ofonod
    make -j$(nproc) src/ofonod || echo "Partial build"
    
    # Manual package if needed
    if [ -f src/ofonod ]; then
        mkdir -p ~/minimal-ofono/usr/sbin
        cp src/ofonod ~/minimal-ofono/usr/sbin/
        arm-linux-gnueabihf-strip ~/minimal-ofono/usr/sbin/ofonod
        cd ~/minimal-ofono
        tar -czf ~/ofono-minimal-arm.tar.gz *
        echo "Created minimal package: ~/ofono-minimal-arm.tar.gz"
    fi
fi

echo -e "\n=== BUILD COMPLETE ==="
echo ""
if [ -f ~/ofono-arm-rv1106.tar.gz ]; then
    echo "Success! Files created:"
    echo "  ~/ofono-arm-rv1106.tar.gz     - Full oFono package"
elif [ -f ~/ofono-minimal-arm.tar.gz ]; then
    echo "Partial success! Created minimal package:"
    echo "  ~/ofono-minimal-arm.tar.gz    - Core oFono daemon only"
fi
echo "  ~/deploy_ofono_rv1106.sh      - Deployment script"
echo ""
echo "Download these files and run the deployment script!"