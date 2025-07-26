#!/bin/bash
# Build script for rtk_hciattach - runs in Codespace/Linux

echo "Building rtk_hciattach for ARM..."

# Clone the source
if [ ! -d "rtk_hciattach" ]; then
    git clone https://github.com/seuscq/rtk_hciattach.git
fi

cd rtk_hciattach

# Create ARM Makefile
cat > Makefile.arm << 'EOF'
CC = arm-linux-gnueabihf-gcc
CFLAGS = -Wall -O2 -static
TARGET = rtk_hciattach

all: $(TARGET)

$(TARGET): hciattach.c hciattach_rtk.o
	$(CC) $(CFLAGS) -o $(TARGET) hciattach.c hciattach_rtk.o

hciattach_rtk.o: hciattach_rtk.c
	$(CC) $(CFLAGS) -c hciattach_rtk.c

clean:
	rm -f *.o $(TARGET)
EOF

# Build
make -f Makefile.arm clean
make -f Makefile.arm

if [ -f rtk_hciattach ]; then
    echo "✓ Build successful!"
    file rtk_hciattach
    ls -la rtk_hciattach
    echo ""
    echo "Download this file and then:"
    echo "adb push rtk_hciattach /tmp/"
    echo "adb shell 'chmod +x /tmp/rtk_hciattach'"
    echo "adb shell '/tmp/rtk_hciattach -n -s 115200 /dev/ttyS5 rtk_h5'"
else
    echo "✗ Build failed"
fi