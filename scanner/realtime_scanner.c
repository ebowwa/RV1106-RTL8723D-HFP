/*
 * Real-time Device Scanner for RV1106
 * Monitors serial and Bluetooth devices in real-time
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <dirent.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <bluetooth/bluetooth.h>
#include <bluetooth/hci.h>
#include <bluetooth/hci_lib.h>
#include <signal.h>
#include <time.h>

#define MAX_DEVICES 256
#define SCAN_INTERVAL 5  // seconds

static volatile int keep_running = 1;

typedef struct {
    char path[64];
    int baud_rate;
    int is_active;
} serial_device_t;

typedef struct {
    bdaddr_t addr;
    char name[248];
    int8_t rssi;
    uint32_t class;
    time_t last_seen;
} bt_device_t;

static serial_device_t serial_devices[MAX_DEVICES];
static bt_device_t bt_devices[MAX_DEVICES];
static int serial_count = 0;
static int bt_count = 0;

void signal_handler(int sig) {
    keep_running = 0;
}

// Get baud rate from serial port
int get_baud_rate(const char *device) {
    int fd = open(device, O_RDONLY | O_NOCTTY | O_NONBLOCK);
    if (fd < 0) return -1;
    
    struct termios tty;
    if (tcgetattr(fd, &tty) != 0) {
        close(fd);
        return -1;
    }
    
    speed_t speed = cfgetispeed(&tty);
    close(fd);
    
    switch(speed) {
        case B9600: return 9600;
        case B19200: return 19200;
        case B38400: return 38400;
        case B57600: return 57600;
        case B115200: return 115200;
        case B230400: return 230400;
        case B460800: return 460800;
        case B921600: return 921600;
        default: return -1;
    }
}

// Scan serial devices
void scan_serial_devices() {
    DIR *dir;
    struct dirent *ent;
    
    serial_count = 0;
    
    if ((dir = opendir("/dev")) != NULL) {
        while ((ent = readdir(dir)) != NULL && serial_count < MAX_DEVICES) {
            if (strncmp(ent->d_name, "ttyS", 4) == 0 ||
                strncmp(ent->d_name, "ttyUSB", 6) == 0 ||
                strncmp(ent->d_name, "ttyACM", 6) == 0) {
                
                snprintf(serial_devices[serial_count].path, 64, "/dev/%s", ent->d_name);
                serial_devices[serial_count].baud_rate = get_baud_rate(serial_devices[serial_count].path);
                serial_devices[serial_count].is_active = (serial_devices[serial_count].baud_rate > 0);
                serial_count++;
            }
        }
        closedir(dir);
    }
}

// Bluetooth inquiry callback
static void bt_inquiry_result(int dev_id, bdaddr_t *bdaddr, uint32_t class, int8_t rssi) {
    char addr[18];
    char name[248] = {0};
    
    ba2str(bdaddr, addr);
    
    // Check if device already in list
    for (int i = 0; i < bt_count; i++) {
        if (bacmp(&bt_devices[i].addr, bdaddr) == 0) {
            bt_devices[i].rssi = rssi;
            bt_devices[i].last_seen = time(NULL);
            return;
        }
    }
    
    // Add new device
    if (bt_count < MAX_DEVICES) {
        bacpy(&bt_devices[bt_count].addr, bdaddr);
        bt_devices[bt_count].class = class;
        bt_devices[bt_count].rssi = rssi;
        bt_devices[bt_count].last_seen = time(NULL);
        
        // Try to get device name
        hci_read_remote_name(dev_id, bdaddr, sizeof(name), name, 0);
        strncpy(bt_devices[bt_count].name, name, sizeof(bt_devices[bt_count].name) - 1);
        
        bt_count++;
    }
}

// Scan Bluetooth devices
void scan_bluetooth_devices() {
    inquiry_info *ii = NULL;
    int max_rsp = 255;
    int num_rsp;
    int dev_id, sock, flags;
    char addr[19] = {0};
    char name[248] = {0};
    
    dev_id = hci_get_route(NULL);
    if (dev_id < 0) {
        printf("No Bluetooth adapter found\n");
        return;
    }
    
    sock = hci_open_dev(dev_id);
    if (sock < 0) {
        printf("Failed to open HCI socket\n");
        return;
    }
    
    flags = IREQ_CACHE_FLUSH;
    ii = (inquiry_info*)malloc(max_rsp * sizeof(inquiry_info));
    
    // Classic Bluetooth scan
    num_rsp = hci_inquiry(dev_id, 8, max_rsp, NULL, &ii, flags);
    if (num_rsp > 0) {
        for (int i = 0; i < num_rsp; i++) {
            bt_inquiry_result(sock, &(ii+i)->bdaddr, 
                            (ii+i)->dev_class[2] << 16 | (ii+i)->dev_class[1] << 8 | (ii+i)->dev_class[0],
                            0);
        }
    }
    
    free(ii);
    
    // TODO: Add BLE scanning using HCI commands
    
    close(sock);
}

// Display results
void display_results() {
    system("clear");
    
    printf("=== RV1106 Real-time Device Scanner ===\n");
    printf("Press Ctrl+C to exit\n\n");
    
    // Display serial devices
    printf("[Serial Devices] Found: %d\n", serial_count);
    printf("%-20s %-15s %s\n", "Device", "Baud Rate", "Status");
    printf("%-20s %-15s %s\n", "------", "---------", "------");
    
    for (int i = 0; i < serial_count; i++) {
        printf("%-20s ", serial_devices[i].path);
        if (serial_devices[i].baud_rate > 0) {
            printf("%-15d ", serial_devices[i].baud_rate);
            printf("Active\n");
        } else {
            printf("%-15s ", "N/A");
            printf("Inactive\n");
        }
    }
    
    // Display Bluetooth devices
    printf("\n[Bluetooth Devices] Found: %d\n", bt_count);
    printf("%-18s %-30s %-8s %s\n", "Address", "Name", "RSSI", "Last Seen");
    printf("%-18s %-30s %-8s %s\n", "-------", "----", "----", "---------");
    
    time_t now = time(NULL);
    char addr[18];
    
    for (int i = 0; i < bt_count; i++) {
        ba2str(&bt_devices[i].addr, addr);
        printf("%-18s ", addr);
        printf("%-30s ", bt_devices[i].name[0] ? bt_devices[i].name : "Unknown");
        printf("%-8d ", bt_devices[i].rssi);
        printf("%lds ago\n", now - bt_devices[i].last_seen);
    }
    
    printf("\nLast update: %s", ctime(&now));
}

int main(int argc, char *argv[]) {
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    printf("Starting device scanner...\n");
    
    while (keep_running) {
        scan_serial_devices();
        scan_bluetooth_devices();
        display_results();
        
        sleep(SCAN_INTERVAL);
    }
    
    printf("\nScanner stopped.\n");
    return 0;
}