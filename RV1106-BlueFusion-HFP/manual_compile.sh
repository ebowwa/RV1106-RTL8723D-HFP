#\!/bin/bash
# Manual compilation steps for rtk_hciattach

echo "Preparing rtk_hciattach for ARM compilation..."

cd rtk_hciattach

# Create a simple build script that can be run on device or with cross-compiler
cat > build_arm.sh << 'BUILD'
#\!/bin/sh
# Build rtk_hciattach for ARM

echo "Building rtk_hciattach..."

# Simple direct compilation
gcc -o rtk_hciattach hciattach.c hciattach_rtk.c \
    -DVERSION=\"1.0\" \
    -D_GNU_SOURCE \
    -Wall

if [ -f rtk_hciattach ]; then
    echo "Build successful\!"
    ls -la rtk_hciattach
else
    echo "Build failed"
fi
BUILD

chmod +x build_arm.sh

# Option 1: Try to compile on device
echo -e "\n=== Option 1: Compile on device ==="
adb push . /tmp/rtk_hciattach_src/
adb shell << 'DEVICE'
cd /tmp/rtk_hciattach_src
if which gcc 2>/dev/null; then
    echo "Found gcc on device, compiling..."
    ./build_arm.sh
    if [ -f rtk_hciattach ]; then
        cp rtk_hciattach /tmp/
        echo "✓ Compiled on device\!"
    fi
else
    echo "No gcc on device"
fi
DEVICE

# Option 2: Use static binary if available
echo -e "\n=== Option 2: Check for pre-built binary ==="

# Create minimal test version
cat > rtk_test.c << 'TEST'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 3) {
        printf("Usage: %s <device> <protocol>\n", argv[0]);
        return 1;
    }
    
    printf("RTK HCI Attach Test\n");
    printf("Device: %s\n", argv[1]);
    printf("Protocol: %s\n", argv[2]);
    
    int fd = open(argv[1], O_RDWR | O_NOCTTY);
    if (fd < 0) {
        perror("open");
        return 1;
    }
    
    struct termios ti;
    tcgetattr(fd, &ti);
    cfmakeraw(&ti);
    cfsetospeed(&ti, B115200);
    cfsetispeed(&ti, B115200);
    tcsetattr(fd, TCSANOW, &ti);
    
    printf("UART configured at 115200\n");
    printf("Sending HCI reset...\n");
    
    // HCI Reset command
    unsigned char reset[] = {0x01, 0x03, 0x0C, 0x00};
    write(fd, reset, 4);
    
    printf("Waiting for response...\n");
    sleep(2);
    
    // Try to change to high speed
    printf("Switching to 1500000 baud...\n");
    cfsetospeed(&ti, B1500000);
    cfsetispeed(&ti, B1500000);
    tcsetattr(fd, TCSANOW, &ti);
    
    printf("Ready for firmware load\n");
    
    // Keep running
    while(1) {
        sleep(1);
    }
    
    return 0;
}
TEST

# Try simple compilation
echo -e "\n=== Option 3: Compile minimal version ==="
if command -v gcc &> /dev/null; then
    gcc -static -o rtk_test rtk_test.c
    if [ -f rtk_test ]; then
        echo "Minimal version compiled"
        adb push rtk_test /tmp/
        adb shell "chmod +x /tmp/rtk_test"
    fi
fi

echo -e "\n=== Available options on device: ==="
adb shell "ls -la /tmp/rtk*"
