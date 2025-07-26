CC = gcc
CFLAGS = -Wall -O2
LDFLAGS = -lbluetooth

# ARM cross-compilation
ARM_CC = arm-linux-gnueabihf-gcc
ARM_CFLAGS = $(CFLAGS)
ARM_LDFLAGS = $(LDFLAGS)

TARGETS = realtime_scanner
ARM_TARGETS = realtime_scanner.arm

all: $(TARGETS)

arm: $(ARM_TARGETS)

realtime_scanner: realtime_scanner.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

realtime_scanner.arm: realtime_scanner.c
	$(ARM_CC) $(ARM_CFLAGS) -o $@ $< $(ARM_LDFLAGS)

clean:
	rm -f $(TARGETS) $(ARM_TARGETS)

deploy: realtime_scanner.arm
	adb push realtime_scanner.arm /tmp/
	adb push device_scanner.py /tmp/
	adb push device_scanner.sh /tmp/
	adb shell "chmod +x /tmp/realtime_scanner.arm /tmp/device_scanner.py /tmp/device_scanner.sh"

.PHONY: all arm clean deploy