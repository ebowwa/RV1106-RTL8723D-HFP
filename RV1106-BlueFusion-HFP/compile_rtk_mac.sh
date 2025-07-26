#!/bin/bash
# Compile rtk_hciattach on macOS for ARM target

echo "🍎 macOS to ARM cross-compilation for rtk_hciattach"
echo "=================================================="

cd rtk_hciattach

# Option 1: Use Homebrew cross-compiler
echo -e "\n📦 Option 1: Using Homebrew ARM toolchain..."
if ! command -v arm-linux-gnueabihf-gcc &> /dev/null; then
    echo "Installing ARM toolchain via Homebrew..."
    brew tap messense/macos-cross-toolchains
    brew install arm-unknown-linux-gnueabihf
fi

if command -v arm-unknown-linux-gnueabihf-gcc &> /dev/null; then
    echo "Found ARM toolchain, compiling..."
    
    # Update Makefile for cross-compilation
    cat > Makefile.arm << 'EOF'
CC = arm-unknown-linux-gnueabihf-gcc
CFLAGS = -Wall -O2

all: rtk_hciattach

rtk_hciattach: hciattach.c hciattach_rtk.o
	$(CC) $(CFLAGS) -o rtk_hciattach hciattach.c hciattach_rtk.o

hciattach_rtk.o: hciattach_rtk.c
	$(CC) $(CFLAGS) -c hciattach_rtk.c

clean:
	rm -f *.o rtk_hciattach
EOF
    
    make -f Makefile.arm clean
    make -f Makefile.arm
    
    if [ -f rtk_hciattach ]; then
        echo "✓ Compilation successful!"
        file rtk_hciattach
        adb push rtk_hciattach /tmp/
        adb shell "chmod +x /tmp/rtk_hciattach"
        echo "✓ Pushed to device"
    fi
else
    echo "❌ Homebrew toolchain not found"
fi

# Option 2: Compile directly on device
echo -e "\n📱 Option 2: Compile directly on RV1106..."

# Create minimal source that might compile with busybox
cat > rtk_minimal.c << 'EOF'
/* Minimal rtk_hciattach for RTL8723D */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <string.h>
#include <errno.h>

#define B1500000 0010012

int main(int argc, char *argv[]) {
    int fd;
    struct termios ti;
    
    printf("RTK HCI Attach (minimal)\n");
    
    fd = open("/dev/ttyS5", O_RDWR | O_NOCTTY);
    if (fd < 0) {
        perror("open");
        return 1;
    }
    
    tcgetattr(fd, &ti);
    cfmakeraw(&ti);
    ti.c_cflag |= CLOCAL | CREAD;
    ti.c_cflag &= ~CRTSCTS;
    
    /* Start at 115200 */
    cfsetospeed(&ti, B115200);
    cfsetispeed(&ti, B115200);
    tcsetattr(fd, TCSANOW, &ti);
    
    printf("Sending initial HCI reset at 115200...\n");
    unsigned char reset[] = {0x01, 0x03, 0x0C, 0x00};
    write(fd, reset, 4);
    sleep(1);
    
    /* Switch to 1500000 */
    printf("Switching to 1500000 baud...\n");
    ti.c_cflag &= ~CBAUD;
    ti.c_cflag |= B1500000;
    tcsetattr(fd, TCSANOW, &ti);
    
    printf("Ready for HCI commands at high speed\n");
    
    /* Keep UART open */
    while(1) sleep(10);
    
    return 0;
}
EOF

# Option 3: Use Docker on macOS
echo -e "\n🐳 Option 3: Docker cross-compilation..."
if command -v docker &> /dev/null; then
    cat > build_docker.sh << 'DOCKER'
#!/bin/bash
docker run --rm -v $PWD:/work -w /work arm32v7/gcc:9 sh -c '
    gcc -static -o rtk_hciattach hciattach.c hciattach_rtk.c -DVERSION=\"1.0\" -D_GNU_SOURCE
    gcc -static -o rtk_minimal rtk_minimal.c
    ls -la rtk_*
'
DOCKER
    
    chmod +x build_docker.sh
    echo "Run ./build_docker.sh if Docker is running"
fi

# Option 4: Pre-built binary
echo -e "\n💾 Option 4: Download pre-built binary..."
echo "Check if available at:"
echo "  https://github.com/rockchip-linux/rkwifibt/tree/master/realtek/rtk_hciattach"

# Push sources to device for local compilation attempt
echo -e "\n📤 Pushing source to device for compilation attempt..."
adb push . /tmp/rtk_src/
adb shell << 'DEVICE'
cd /tmp/rtk_src
# Try to find any compiler
for CC in gcc cc clang tcc; do
    if which $CC 2>/dev/null; then
        echo "Found $CC, attempting compilation..."
        $CC -o rtk_minimal rtk_minimal.c
        if [ -f rtk_minimal ]; then
            chmod +x rtk_minimal
            cp rtk_minimal /tmp/
            echo "✓ Minimal version compiled on device!"
            break
        fi
    fi
done

# If no compiler, try static linking from busybox
if [ ! -f /tmp/rtk_minimal ]; then
    echo "No compiler found on device"
fi
DEVICE

echo -e "\n✅ Next steps:"
echo "1. If compilation succeeded: adb shell '/tmp/rtk_hciattach -n -s 115200 /dev/ttyS5 rtk_h5'"
echo "2. Alternative: adb shell '/tmp/rtk_minimal'"
echo "3. Or use the working init script at 1500000 baud"