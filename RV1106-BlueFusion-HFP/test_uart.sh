#!/bin/sh
# Test UART communication with RTL8723D

echo "Testing UART /dev/ttyS5..."

# Configure UART
stty -F /dev/ttyS5 115200 cs8 -cstopb -parenb raw -echo

# Send HCI Reset command (01 03 0C 00)
echo -ne '\x01\x03\x0C\x00' > /dev/ttyS5

# Try to read response
echo "Waiting for response..."
timeout 2 cat /dev/ttyS5 | hexdump -C | head -10

echo ""
echo "Testing with minicom..."
# Test with minicom if available
which minicom && timeout 5 minicom -D /dev/ttyS5 -b 115200