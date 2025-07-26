#!/bin/bash
# Compile rtk_hciattach directly on device using busybox

echo "Attempting to compile rtk_hciattach on device..."

# Create simplified source that might compile without full toolchain
cat > /tmp/rtk_hciattach_minimal.c << 'EOF'
/* Minimal rtk_hciattach for RTL8723D */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <string.h>
#include <sys/ioctl.h>

int main(int argc, char *argv[]) {
    int fd;
    struct termios ti;
    char *device = "/dev/ttyS5";
    
    if (argc > 1) device = argv[1];
    
    printf("Opening %s...\n", device);
    fd = open(device, O_RDWR | O_NOCTTY);
    if (fd < 0) {
        perror("open");
        return 1;
    }
    
    /* Configure UART */
    tcgetattr(fd, &ti);
    cfmakeraw(&ti);
    ti.c_cflag |= CLOCAL | CREAD;
    ti.c_cflag &= ~CRTSCTS;
    cfsetospeed(&ti, B115200);
    cfsetispeed(&ti, B115200);
    tcsetattr(fd, TCSANOW, &ti);
    
    printf("Sending HCI Reset...\n");
    /* Send HCI Reset: 01 03 0C 00 */
    unsigned char reset[] = {0x01, 0x03, 0x0C, 0x00};
    write(fd, reset, 4);
    
    sleep(1);
    
    printf("RTL8723D initialization started\n");
    printf("Use 'hciconfig hci0 up' to complete\n");
    
    /* Keep UART open */
    while(1) sleep(1);
    
    return 0;
}
EOF

# Push to device
adb push /tmp/rtk_hciattach_minimal.c /tmp/

# Try to compile on device
adb shell << 'COMPILE'
cd /tmp
echo "Checking for compiler..."

# Try different compilers
for CC in cc gcc clang tcc; do
    if which $CC 2>/dev/null; then
        echo "Found $CC, compiling..."
        $CC -o rtk_hciattach_minimal rtk_hciattach_minimal.c
        if [ -f rtk_hciattach_minimal ]; then
            echo "Compilation successful!"
            chmod +x rtk_hciattach_minimal
            ./rtk_hciattach_minimal /dev/ttyS5 &
            sleep 2
            hciconfig -a
            exit 0
        fi
    fi
done

echo "No compiler found. Trying alternative..."

# Alternative: Use pre-existing hciattach with wrapper
cat > /tmp/rtk_init.sh << 'SCRIPT'
#!/bin/sh
# RTL8723D initialization wrapper

# Kill existing
killall hciattach btattach 2>/dev/null

# Create firmware links
mkdir -p /lib/firmware/rtl_bt
ln -sf /lib/firmware/rtlbt/rtl8723d_fw /lib/firmware/rtl8723d_fw.bin
ln -sf /lib/firmware/rtlbt/rtl8723d_config /lib/firmware/rtl8723d_config.bin

# Try with 'any' protocol at high speed
echo "Initializing at 1500000 baud..."
hciattach /dev/ttyS5 any 1500000 flow noflow &
PID=$!

sleep 3

# Check if it worked
if hciconfig hci0 2>/dev/null; then
    echo "HCI created, sending initialization..."
    
    # Send vendor commands
    hcitool cmd 0x3f 0x0001 0x01  # Download mode
    sleep 0.5
    hcitool cmd 0x03 0x0003        # Reset
    sleep 1
    
    hciconfig hci0 up
    hciconfig -a
else
    echo "Failed to create HCI"
    kill $PID 2>/dev/null
fi
SCRIPT

chmod +x /tmp/rtk_init.sh
/tmp/rtk_init.sh
COMPILE