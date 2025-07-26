# On-Device Development for RV1106

## 1. Native C/C++ Implementation (Runs on Device)

### a) Lightweight HFP Stack
```c
// src/native/hfp_minimal.c
#include <bluetooth/bluetooth.h>
#include <bluetooth/hci.h>
#include <bluetooth/hci_lib.h>
#include <bluetooth/rfcomm.h>
#include <bluetooth/sco.h>

struct hfp_connection {
    int rfcomm_sock;
    int sco_sock;
    bdaddr_t remote_addr;
    uint8_t state;
    uint8_t codec;
};

// Minimal HFP implementation focused on stability
int hfp_init_rtl8723d() {
    // Direct hardware initialization
    int fd = open("/dev/ttyS5", O_RDWR | O_NOCTTY);
    
    // Configure UART for RTL8723D
    struct termios tty;
    tcgetattr(fd, &tty);
    cfsetospeed(&tty, B1500000);  // 1.5Mbps for RTL8723D
    
    // Load firmware directly
    load_rtl_firmware(fd, "/lib/firmware/rtlbt/rtl8723d_fw");
    
    // Initialize HCI
    return init_hci_device(fd);
}
```

### b) Kernel Module for RTL8723D
```c
// kernel/rtl8723d_bt.ko
static int rtl8723d_probe(struct platform_device *pdev) {
    struct device_node *np = pdev->dev.of_node;
    
    // Get GPIO pins from device tree
    bt_reset_gpio = of_get_named_gpio(np, "reset-gpios", 0);
    bt_wake_gpio = of_get_named_gpio(np, "device-wake-gpios", 0);
    
    // Power sequence
    gpio_set_value(bt_reset_gpio, 0);
    msleep(10);
    gpio_set_value(bt_reset_gpio, 1);
    
    // Register with Bluetooth subsystem
    return hci_uart_register_device(&rtl8723d_uart, &rtl_proto);
}
```

## 2. System Service Implementation

### a) Init.d Script
```bash
#!/bin/sh
# /etc/init.d/rtl8723d-bluetooth

start() {
    echo "Starting RTL8723D Bluetooth..."
    
    # GPIO initialization
    echo 110 > /sys/class/gpio/export
    echo out > /sys/class/gpio/gpio110/direction
    echo 0 > /sys/class/gpio/gpio110/value
    sleep 0.1
    echo 1 > /sys/class/gpio/gpio110/value
    
    # Load firmware
    /usr/bin/rtk_hciattach -n -s 1500000 /dev/ttyS5 rtk_h5 &
    
    # Wait for HCI
    sleep 2
    
    # Configure for HFP
    hciconfig hci0 up
    hciconfig hci0 piscan
    hciconfig hci0 sspmode 1
    
    # Start BlueALSA with optimized settings
    bluealsa -p hfp-hf --hfp-codec=cvsd \
        --sco-routing=hci \
        --io-thread-rt-priority=99 &
}
```

### b) BlueALSA Configuration Patch
```diff
--- a/src/bluealsa/ba-transport.c
+++ b/src/bluealsa/ba-transport.c
@@ -456,6 +456,15 @@ int ba_transport_start(struct ba_transport *t) {
+    /* RV1106 + RTL8723D specific optimizations */
+    if (t->type.codec == HFP_CODEC_CVSD) {
+        /* Force CVSD-only mode for stability */
+        t->codec_negotiation_disabled = true;
+        
+        /* Optimize SCO parameters */
+        sco_options.mtu = 48;  /* Smaller MTU for RTL8723D */
+        sco_options.flush_timeout = 0xFFFF;  /* No flush */
+    }
```

## 3. Buildroot Package

### a) Package Definition
```makefile
# buildroot/package/rtl8723d-bt/rtl8723d-bt.mk
RTL8723D_BT_VERSION = 1.0
RTL8723D_BT_SITE = $(BR2_EXTERNAL_RV1106_PATH)/package/rtl8723d-bt
RTL8723D_BT_SITE_METHOD = local
RTL8723D_BT_LICENSE = GPL-2.0

define RTL8723D_BT_BUILD_CMDS
    $(MAKE) CC="$(TARGET_CC)" LD="$(TARGET_LD)" -C $(@D) all
endef

define RTL8723D_BT_INSTALL_TARGET_CMDS
    $(INSTALL) -D -m 0755 $(@D)/rtk_hciattach $(TARGET_DIR)/usr/bin/
    $(INSTALL) -D -m 0755 $(@D)/rtl8723d-init $(TARGET_DIR)/usr/bin/
    $(INSTALL) -D -m 0644 $(@D)/rtl8723d.conf $(TARGET_DIR)/etc/bluetooth/
endef

$(eval $(generic-package))
```

### b) Device Tree Overlay
```dts
// arch/arm/boot/dts/rv1106-bluetooth.dtsi
&uart5 {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&uart5_xfer &uart5_cts>;
    
    bluetooth {
        compatible = "realtek,rtl8723d";
        reset-gpios = <&gpio3 RK_PB1 GPIO_ACTIVE_HIGH>;
        device-wake-gpios = <&gpio3 RK_PB2 GPIO_ACTIVE_HIGH>;
        host-wake-gpios = <&gpio3 RK_PB3 GPIO_ACTIVE_HIGH>;
        max-speed = <1500000>;
        
        // Audio routing
        pcm-routing = "disabled";  // Force SCO over HCI
    };
};
```

## 4. Optimized Audio Pipeline

### a) ALSA Configuration
```
# /etc/asound.conf
pcm.!default {
    type plug
    slave.pcm "bluealsa"
}

pcm.bluealsa {
    type bluealsa
    device "XX:XX:XX:XX:XX:XX"
    profile "sco"
    # RTL8723D specific: smaller buffer for lower latency
    buffer_time 10000  # 10ms
    period_time 5000   # 5ms
}

# Hardware volume control
ctl.!default {
    type bluealsa
}
```

### b) Real-time Audio Thread
```c
// src/native/sco_processor.c
#include <pthread.h>
#include <sched.h>

void* sco_audio_thread(void* arg) {
    struct sched_param param;
    param.sched_priority = 99;
    
    // Set real-time priority
    pthread_setschedparam(pthread_self(), SCHED_FIFO, &param);
    
    // Pin to CPU core
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(0, &cpuset);
    pthread_setaffinity_np(pthread_self(), sizeof(cpuset), &cpuset);
    
    // Process SCO audio with minimal latency
    while (running) {
        // Read SCO packet
        read(sco_fd, buffer, 48);
        
        // Optional: Apply DSP (echo cancellation, etc.)
        if (enable_dsp) {
            process_audio(buffer, 48);
        }
        
        // Write to audio output
        write(audio_fd, buffer, 48);
    }
}
```

## 5. Debugging Tools (On-Device)

### a) HCI Logger
```c
// tools/hci_logger.c
int main() {
    int dd = hci_open_dev(0);
    struct hci_filter flt;
    
    // Set filter for HFP-related events
    hci_filter_clear(&flt);
    hci_filter_set_ptype(HCI_EVENT_PKT, &flt);
    hci_filter_set_event(EVT_CONN_COMPLETE, &flt);
    hci_filter_set_event(EVT_DISCONN_COMPLETE, &flt);
    hci_filter_set_event(EVT_SYNC_CONN_COMPLETE, &flt);
    
    setsockopt(dd, SOL_HCI, HCI_FILTER, &flt, sizeof(flt));
    
    // Log to file with rotation
    FILE* log = fopen("/var/log/hfp_debug.log", "a");
    
    while (1) {
        // Read and log HCI events
        len = read(dd, buf, sizeof(buf));
        log_hci_event(log, buf, len);
    }
}
```

### b) Connection Monitor Script
```sh
#!/bin/sh
# /usr/bin/hfp_monitor.sh

# Run on device with minimal overhead
while true; do
    # Check HCI status
    STATUS=$(hciconfig hci0 | grep "UP RUNNING")
    
    # Check BlueALSA
    BLUEALSA=$(pidof bluealsa)
    
    # Check active connections
    CONNECTIONS=$(hcitool con | grep -c "ACL")
    SCO=$(hcitool con | grep -c "SCO")
    
    # Log to syslog
    logger "HFP Monitor: HCI=$STATUS BA=$BLUEALSA ACL=$CONNECTIONS SCO=$SCO"
    
    # Auto-recovery if needed
    if [ -z "$STATUS" ]; then
        logger "HFP Monitor: Restarting Bluetooth..."
        /etc/init.d/rtl8723d-bluetooth restart
    fi
    
    sleep 10
done
```

## 6. Performance Optimizations

### a) CPU Governor Settings
```bash
# /etc/init.d/performance-tuning
#!/bin/sh

# Set performance governor for audio
echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# Disable CPU idle states for lower latency
echo 1 > /sys/devices/system/cpu/cpu0/cpuidle/state0/disable
echo 1 > /sys/devices/system/cpu/cpu0/cpuidle/state1/disable

# Increase HCI UART priority
chrt -f -p 90 $(pidof hciattach)
```

### b) Memory Optimization
```c
// Compile with: -Os -ffunction-sections -fdata-sections -Wl,--gc-sections

// Use static allocation for critical paths
static uint8_t sco_buffer[SCO_MTU] __attribute__((aligned(64)));
static struct hfp_state hfp_states[MAX_CONNECTIONS];

// Disable malloc in audio path
#define NO_DYNAMIC_ALLOCATION
```

## 7. Factory Test Mode

```c
// tools/factory_test.c
int factory_test_hfp() {
    printf("=== RTL8723D HFP Factory Test ===\n");
    
    // 1. Initialize hardware
    if (!init_rtl8723d()) {
        printf("FAIL: Hardware initialization\n");
        return -1;
    }
    
    // 2. Loopback test
    if (!test_sco_loopback()) {
        printf("FAIL: SCO loopback\n");
        return -1;
    }
    
    // 3. Audio quality test
    float mos = test_audio_quality();
    printf("Audio MOS Score: %.2f\n", mos);
    
    // 4. Connection stress test
    int failures = stress_test_connections(100);
    printf("Connection failures: %d/100\n", failures);
    
    return (mos > 3.5 && failures < 5) ? 0 : -1;
}
```

## 8. OTA Update Support

```sh
#!/bin/sh
# /usr/bin/update_bluetooth_fw.sh

# Download new firmware
wget -q http://update.server/rtl8723d_fw.bin -O /tmp/rtl8723d_fw.new

# Verify checksum
if [ "$(md5sum /tmp/rtl8723d_fw.new | cut -d' ' -f1)" != "$EXPECTED_MD5" ]; then
    echo "Firmware verification failed"
    exit 1
fi

# Backup current
cp /lib/firmware/rtlbt/rtl8723d_fw /lib/firmware/rtlbt/rtl8723d_fw.bak

# Install new firmware
mv /tmp/rtl8723d_fw.new /lib/firmware/rtlbt/rtl8723d_fw

# Restart Bluetooth
/etc/init.d/rtl8723d-bluetooth restart

# Test connection
if ! hciconfig hci0 up; then
    # Rollback
    mv /lib/firmware/rtlbt/rtl8723d_fw.bak /lib/firmware/rtlbt/rtl8723d_fw
    /etc/init.d/rtl8723d-bluetooth restart
    exit 1
fi

echo "Firmware updated successfully"
```

## Build Instructions

```bash
# 1. Setup cross-compile environment
export CROSS_COMPILE=arm-linux-gnueabihf-
export ARCH=arm

# 2. Build kernel module
make -C kernel/rtl8723d_bt

# 3. Build userspace tools
make -C tools/

# 4. Create deployment package
tar czf rv1106-bluetooth-${VERSION}.tar.gz \
    kernel/rtl8723d_bt.ko \
    tools/rtk_hciattach \
    tools/hfp_monitor \
    scripts/init.d/rtl8723d-bluetooth \
    configs/asound.conf

# 5. Deploy to device
scp rv1106-bluetooth-${VERSION}.tar.gz root@rv1106:/tmp/
ssh root@rv1106 "cd / && tar xzf /tmp/rv1106-bluetooth-${VERSION}.tar.gz"
```

This on-device development approach provides:
- Native performance
- Minimal resource usage
- Direct hardware control
- Real-time audio processing
- Automatic recovery mechanisms
- Factory testing capabilities