# Building oFono for RV1106 (ARM)

## Why oFono?

From the PDF analysis:
- BlueALSA's HFP-HF (client) implementation is broken
- Error: "Too small packet for stream_rej" 
- oFono provides proper HFP support for phone calls

## Building oFono

### 1. Set up GitHub Codespace (for macOS users)

```bash
# Create a new Codespace with Ubuntu
# Install ARM cross-compiler
sudo apt-get update
sudo apt-get install -y \
    gcc-arm-linux-gnueabihf \
    g++-arm-linux-gnueabihf \
    libc6-dev-armhf-cross \
    pkg-config \
    autoconf \
    automake \
    libtool
```

### 2. Get oFono source

```bash
git clone https://git.kernel.org/pub/scm/network/ofono/ofono.git
cd ofono
git checkout 1.34  # Stable version
```

### 3. Install dependencies

```bash
# For cross-compilation, you need ARM versions of:
# - D-Bus
# - GLib
# - Bluetooth libraries

# Option A: Use pre-built ARM libraries
sudo apt-get install -y \
    libdbus-1-dev:armhf \
    libglib2.0-dev:armhf \
    libbluetooth-dev:armhf

# Option B: Build from source for ARM
```

### 4. Configure for ARM

```bash
export CC=arm-linux-gnueabihf-gcc
export CXX=arm-linux-gnueabihf-g++
export AR=arm-linux-gnueabihf-ar
export STRIP=arm-linux-gnueabihf-strip

./bootstrap
./configure \
    --host=arm-linux-gnueabihf \
    --prefix=/usr \
    --sysconfdir=/etc \
    --localstatedir=/var \
    --disable-udev \
    --disable-systemd \
    --enable-bluetooth \
    --enable-tools
```

### 5. Build

```bash
make -j4
make DESTDIR=$PWD/install install
```

### 6. Package for deployment

```bash
cd install
tar -czf ofono-arm.tar.gz *
```

## Deployment to RV1106

```bash
# Copy to device
adb push ofono-arm.tar.gz /tmp/

# Extract on device
adb shell "cd / && tar -xzf /tmp/ofono-arm.tar.gz"

# Create config directory
adb shell "mkdir -p /etc/ofono"

# Create basic config
cat > phonesim.conf << EOF
[phonesim]
Driver=phonesim
Address=127.0.0.1
Port=12345
EOF
adb push phonesim.conf /etc/ofono/
```

## Running oFono with BlueALSA

```bash
#!/bin/sh
# Start oFono for HFP

# Start D-Bus
dbus-daemon --system &

# Start BlueZ
bluetoothd --experimental &

# Start oFono (handles HFP)
ofonod -n -d &

# Start BlueALSA (handles A2DP only)
bluealsa -p a2dp-sink -p a2dp-source &
```

## Testing HFP with oFono

```bash
# List modems
dbus-send --system --print-reply \
    --dest=org.ofono / \
    org.ofono.Manager.GetModems

# Monitor HFP
dbus-monitor --system \
    "type='signal',interface='org.ofono.Modem'"
```

## Alternative: Use existing package

If your RV1106 has a package manager:

```bash
# Buildroot
make menuconfig
# Enable: Target packages -> Libraries -> Other -> ofono

# OpenWrt
opkg update
opkg install ofono

# Yocto
IMAGE_INSTALL_append = " ofono"
```

## Summary

oFono provides:
- Proper HFP-HF implementation
- AT command handling
- SCO audio management
- Phone call control

This solves the "Too small packet for stream_rej" error shown in the PDF.