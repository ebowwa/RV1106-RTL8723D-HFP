#!/bin/bash
# Build script for rtk_hciattach

echo "Building rtk_hciattach for ARM..."

# Check if we're in a codespace or have cross-compiler
if command -v arm-linux-gnueabihf-gcc &> /dev/null; then
    echo "Using ARM cross-compiler..."
    CC=arm-linux-gnueabihf-gcc
elif [ -f /.dockerenv ]; then
    echo "Running in Docker..."
    CC=gcc
else
    echo "Installing dependencies..."
    sudo apt-get update
    sudo apt-get install -y gcc-arm-linux-gnueabihf
    CC=arm-linux-gnueabihf-gcc
fi

# Clone source if not present
if [ ! -f hciattach.c ]; then
    echo "Cloning rtk_hciattach source..."
    git clone https://github.com/seuscq/rtk_hciattach.git .
fi

# Build
echo "Compiling..."
$CC -Wall -O2 -static -o rtk_hciattach hciattach.c hciattach_rtk.c

if [ -f rtk_hciattach ]; then
    echo "✓ Build successful!"
    file rtk_hciattach
    ls -la rtk_hciattach
    echo ""
    echo "To deploy:"
    echo "adb push rtk_hciattach /tmp/"
    echo "adb shell 'chmod +x /tmp/rtk_hciattach'"
    echo "adb shell '/tmp/rtk_hciattach -n -s 115200 /dev/ttyS5 rtk_h5'"
else
    echo "✗ Build failed"
    exit 1
fi