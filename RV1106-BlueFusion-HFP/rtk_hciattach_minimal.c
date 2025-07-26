/* Minimal rtk_hciattach implementation for RTL8723D
 * Compile: arm-linux-gnueabihf-gcc -static -o rtk_hciattach rtk_hciattach_minimal.c
 * Or use online compiler: https://godbolt.org/
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <string.h>
#include <errno.h>
#include <sys/ioctl.h>

#define B1500000 0010012
#define FIRMWARE_PATH "/lib/firmware/rtlbt/rtl8723d_fw"
#define CONFIG_PATH "/lib/firmware/rtlbt/rtl8723d_config"

/* HCI Commands */
#define HCI_COMMAND_PKT 0x01
#define HCI_RESET 0x0c03
#define HCI_VSC_UPDATE_BAUDRATE 0xfc17
#define HCI_VSC_DOWNLOAD_FW 0xfc20

int uart_fd = -1;

int init_uart(const char *device, int baudrate) {
    struct termios ti;
    
    uart_fd = open(device, O_RDWR | O_NOCTTY);
    if (uart_fd < 0) {
        perror("open uart");
        return -1;
    }
    
    tcflush(uart_fd, TCIOFLUSH);
    
    if (tcgetattr(uart_fd, &ti) < 0) {
        perror("tcgetattr");
        return -1;
    }
    
    cfmakeraw(&ti);
    ti.c_cflag |= CLOCAL | CREAD;
    ti.c_cflag &= ~CRTSCTS;
    
    cfsetospeed(&ti, baudrate);
    cfsetispeed(&ti, baudrate);
    
    if (tcsetattr(uart_fd, TCSANOW, &ti) < 0) {
        perror("tcsetattr");
        return -1;
    }
    
    tcflush(uart_fd, TCIOFLUSH);
    return 0;
}

int send_hci_cmd(uint16_t opcode, uint8_t *params, uint8_t len) {
    uint8_t cmd[260] = {0};
    
    cmd[0] = HCI_COMMAND_PKT;
    cmd[1] = opcode & 0xff;
    cmd[2] = (opcode >> 8) & 0xff;
    cmd[3] = len;
    
    if (len > 0 && params) {
        memcpy(&cmd[4], params, len);
    }
    
    return write(uart_fd, cmd, 4 + len);
}

int main(int argc, char *argv[]) {
    const char *device = "/dev/ttyS5";
    
    printf("RTK HCI Attach for RTL8723D\n");
    printf("===========================\n");
    
    if (argc > 1) device = argv[1];
    
    /* Step 1: Initialize at 115200 */
    printf("1. Initializing UART at 115200...\n");
    if (init_uart(device, B115200) < 0) {
        return 1;
    }
    
    /* Step 2: Send HCI Reset */
    printf("2. Sending HCI Reset...\n");
    send_hci_cmd(HCI_RESET, NULL, 0);
    sleep(1);
    
    /* Step 3: Switch to high speed */
    printf("3. Switching to 1500000 baud...\n");
    uint8_t baudrate_cmd[] = {0x00, 0x00, 0xe0, 0x16}; /* 1500000 baud */
    send_hci_cmd(HCI_VSC_UPDATE_BAUDRATE, baudrate_cmd, 4);
    usleep(50000);
    
    /* Reinit UART at high speed */
    close(uart_fd);
    if (init_uart(device, B1500000) < 0) {
        return 1;
    }
    
    /* Step 4: Download firmware */
    printf("4. Starting firmware download...\n");
    uint8_t dl_cmd[] = {0x00}; /* Start download */
    send_hci_cmd(HCI_VSC_DOWNLOAD_FW, dl_cmd, 1);
    
    printf("5. Firmware loading initiated\n");
    printf("\nKeeping UART open for hciattach...\n");
    
    /* Keep running */
    while (1) {
        sleep(10);
    }
    
    return 0;
}