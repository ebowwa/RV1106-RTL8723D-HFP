/*
 * Realtek RTL8723D HCI Attach Tool
 * Optimized for RV1106 platform
 * 
 * Compile: arm-linux-gnueabihf-gcc -O2 -o rtk_hciattach rtk_hciattach.c
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <linux/tty.h>

#define RTL_FIRMWARE_DIR    "/lib/firmware/rtlbt/"
#define RTL8723D_FW_FILE   "rtl8723d_fw"
#define RTL8723D_CONFIG    "rtl8723d_config"

#define HCI_COMMAND_PKT     0x01
#define HCI_EVENT_PKT       0x04
#define HCI_VENDOR_PKT      0x0E

#define H5_HDR_SIZE         4
#define H5_CRC_SIZE         2

/* H5 protocol states */
enum {
    H5_UNINITIALIZED,
    H5_INITIALIZED,
    H5_ACTIVE
};

/* HCI commands */
#define HCI_OP_RESET            0x0C03
#define HCI_OP_READ_LOCAL_VER   0x1001
#define HCI_OP_VENDOR_CMD       0xFC20

struct rtl_fw_header {
    uint8_t signature[8];
    uint16_t version;
    uint16_t num_patches;
    uint32_t patch_length;
} __attribute__((packed));

struct h5_struct {
    int state;
    uint8_t tx_seq;
    uint8_t tx_ack;
    uint8_t rx_seq;
    uint8_t rx_ack;
    int uart_fd;
};

static int uart_speed_to_baud(int speed)
{
    switch (speed) {
    case 9600:      return B9600;
    case 19200:     return B19200;
    case 38400:     return B38400;
    case 57600:     return B57600;
    case 115200:    return B115200;
    case 230400:    return B230400;
    case 460800:    return B460800;
    case 921600:    return B921600;
    case 1500000:   return B1500000;
    default:        return B115200;
    }
}

static int init_uart(const char *dev, int speed)
{
    struct termios ti;
    int fd;

    fd = open(dev, O_RDWR | O_NOCTTY);
    if (fd < 0) {
        perror("open uart");
        return -1;
    }

    tcflush(fd, TCIOFLUSH);

    if (tcgetattr(fd, &ti) < 0) {
        perror("tcgetattr");
        close(fd);
        return -1;
    }

    cfmakeraw(&ti);

    ti.c_cflag |= CLOCAL | CREAD;
    ti.c_cflag &= ~CRTSCTS;
    ti.c_cflag &= ~CSIZE;
    ti.c_cflag |= CS8;
    ti.c_cflag &= ~PARENB;
    ti.c_cflag &= ~CSTOPB;

    ti.c_cc[VMIN] = 1;
    ti.c_cc[VTIME] = 0;

    cfsetospeed(&ti, uart_speed_to_baud(speed));
    cfsetispeed(&ti, uart_speed_to_baud(speed));

    if (tcsetattr(fd, TCSANOW, &ti) < 0) {
        perror("tcsetattr");
        close(fd);
        return -1;
    }

    tcflush(fd, TCIOFLUSH);

    return fd;
}

static uint8_t h5_crc(const uint8_t *data, int len)
{
    uint8_t crc = 0;
    int i;

    for (i = 0; i < len; i++)
        crc ^= data[i];

    return crc;
}

static int h5_send_packet(struct h5_struct *h5, uint8_t pkt_type, 
                         const uint8_t *data, int len)
{
    uint8_t hdr[H5_HDR_SIZE];
    uint8_t pkt[512];
    int pkt_len = 0;

    /* SLIP start */
    pkt[pkt_len++] = 0xC0;

    /* H5 header */
    hdr[0] = h5->tx_ack;
    hdr[1] = h5->tx_seq << 3 | pkt_type;
    hdr[2] = len & 0xFF;
    hdr[3] = len >> 8;

    memcpy(pkt + pkt_len, hdr, H5_HDR_SIZE);
    pkt_len += H5_HDR_SIZE;

    /* Payload */
    if (data && len > 0) {
        memcpy(pkt + pkt_len, data, len);
        pkt_len += len;
    }

    /* CRC */
    pkt[pkt_len++] = h5_crc(hdr, H5_HDR_SIZE) ^ h5_crc(data, len);

    /* SLIP end */
    pkt[pkt_len++] = 0xC0;

    /* Send packet */
    if (write(h5->uart_fd, pkt, pkt_len) != pkt_len) {
        perror("write");
        return -1;
    }

    h5->tx_seq = (h5->tx_seq + 1) & 0x07;

    return 0;
}

static int h5_recv_packet(struct h5_struct *h5, uint8_t *pkt_type,
                         uint8_t *data, int max_len)
{
    uint8_t byte;
    uint8_t hdr[H5_HDR_SIZE];
    int state = 0;
    int len = 0;
    int payload_len = 0;
    int timeout = 1000; /* 1 second timeout */

    while (timeout-- > 0) {
        if (read(h5->uart_fd, &byte, 1) != 1) {
            usleep(1000);
            continue;
        }

        switch (state) {
        case 0: /* Wait for SLIP start */
            if (byte == 0xC0)
                state = 1;
            break;

        case 1: /* Read header */
            hdr[len++] = byte;
            if (len == H5_HDR_SIZE) {
                h5->rx_ack = hdr[0] & 0x07;
                h5->rx_seq = (hdr[1] >> 3) & 0x07;
                *pkt_type = hdr[1] & 0x0F;
                payload_len = hdr[2] | (hdr[3] << 8);
                len = 0;
                state = 2;
            }
            break;

        case 2: /* Read payload */
            if (len < payload_len && len < max_len) {
                data[len++] = byte;
            } else {
                state = 3;
            }
            break;

        case 3: /* Read CRC */
            state = 4;
            break;

        case 4: /* Wait for SLIP end */
            if (byte == 0xC0) {
                return len;
            }
            break;
        }
    }

    return -1;
}

static int hci_send_cmd(struct h5_struct *h5, uint16_t opcode,
                       const uint8_t *params, int plen)
{
    uint8_t cmd[256];
    int len = 0;

    cmd[len++] = HCI_COMMAND_PKT;
    cmd[len++] = opcode & 0xFF;
    cmd[len++] = opcode >> 8;
    cmd[len++] = plen;

    if (params && plen > 0) {
        memcpy(cmd + len, params, plen);
        len += plen;
    }

    return h5_send_packet(h5, HCI_COMMAND_PKT, cmd, len);
}

static int wait_for_event(struct h5_struct *h5, uint8_t event_code,
                         uint8_t *data, int max_len)
{
    uint8_t pkt_type;
    uint8_t buf[256];
    int len;
    int retries = 10;

    while (retries-- > 0) {
        len = h5_recv_packet(h5, &pkt_type, buf, sizeof(buf));
        if (len < 0)
            continue;

        if (pkt_type == HCI_EVENT_PKT && buf[0] == event_code) {
            if (data && max_len > 0) {
                int copy_len = (len - 2 < max_len) ? len - 2 : max_len;
                memcpy(data, buf + 2, copy_len);
            }
            return len - 2;
        }
    }

    return -1;
}

static int rtl_read_local_version(struct h5_struct *h5, uint16_t *lmp_subver)
{
    uint8_t resp[14];
    int len;

    if (hci_send_cmd(h5, HCI_OP_READ_LOCAL_VER, NULL, 0) < 0)
        return -1;

    len = wait_for_event(h5, 0x0E, resp, sizeof(resp));
    if (len < 14)
        return -1;

    *lmp_subver = resp[12] | (resp[13] << 8);
    return 0;
}

static int rtl_load_firmware(struct h5_struct *h5, const char *fw_file,
                            const char *config_file)
{
    FILE *fp;
    uint8_t *fw_data = NULL;
    uint8_t *config_data = NULL;
    struct rtl_fw_header *hdr;
    size_t fw_size, config_size;
    int ret = -1;
    uint8_t cmd[256];
    int frag_len;
    int offset;

    /* Load firmware file */
    fp = fopen(fw_file, "rb");
    if (!fp) {
        fprintf(stderr, "Failed to open firmware: %s\n", fw_file);
        return -1;
    }

    fseek(fp, 0, SEEK_END);
    fw_size = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    fw_data = malloc(fw_size);
    if (!fw_data) {
        fclose(fp);
        return -1;
    }

    if (fread(fw_data, 1, fw_size, fp) != fw_size) {
        fclose(fp);
        goto cleanup;
    }
    fclose(fp);

    /* Check firmware header */
    hdr = (struct rtl_fw_header *)fw_data;
    if (memcmp(hdr->signature, "Realtech", 8) != 0) {
        fprintf(stderr, "Invalid firmware signature\n");
        goto cleanup;
    }

    printf("Firmware: %d patches, %d bytes each\n",
           hdr->num_patches, hdr->patch_length);

    /* Load config file */
    fp = fopen(config_file, "rb");
    if (fp) {
        fseek(fp, 0, SEEK_END);
        config_size = ftell(fp);
        fseek(fp, 0, SEEK_SET);

        config_data = malloc(config_size);
        if (config_data) {
            fread(config_data, 1, config_size, fp);
        }
        fclose(fp);
    }

    /* Enter download mode */
    cmd[0] = 0x01;
    if (hci_send_cmd(h5, 0xFC01, cmd, 1) < 0)
        goto cleanup;

    wait_for_event(h5, 0x0E, NULL, 0);

    /* Download firmware patches */
    offset = sizeof(struct rtl_fw_header);
    while (offset < fw_size) {
        frag_len = (fw_size - offset > 252) ? 252 : fw_size - offset;

        cmd[0] = 0x01;  /* Download opcode */
        cmd[1] = frag_len + 1;
        cmd[2] = (offset == sizeof(struct rtl_fw_header)) ? 0x00 : 0x01;
        memcpy(cmd + 3, fw_data + offset, frag_len);

        if (hci_send_cmd(h5, HCI_OP_VENDOR_CMD, cmd, frag_len + 3) < 0)
            goto cleanup;

        wait_for_event(h5, 0x0E, NULL, 0);

        offset += frag_len;
        printf("\rFirmware download: %d%%", offset * 100 / fw_size);
        fflush(stdout);
    }
    printf("\n");

    /* Download config if available */
    if (config_data && config_size > 0) {
        cmd[0] = 0x08;  /* Config opcode */
        cmd[1] = config_size;
        memcpy(cmd + 2, config_data, config_size);

        if (hci_send_cmd(h5, 0xFC61, cmd, config_size + 2) < 0)
            goto cleanup;

        wait_for_event(h5, 0x0E, NULL, 0);
    }

    /* Launch firmware */
    cmd[0] = 0x00;
    if (hci_send_cmd(h5, 0xFC01, cmd, 1) < 0)
        goto cleanup;

    wait_for_event(h5, 0x0E, NULL, 0);

    ret = 0;
    printf("Firmware loaded successfully\n");

cleanup:
    free(fw_data);
    free(config_data);
    return ret;
}

static int rtl_set_baudrate(struct h5_struct *h5, int baudrate)
{
    uint8_t cmd[4];
    struct termios ti;

    /* Send vendor command to change baud rate */
    cmd[0] = baudrate & 0xFF;
    cmd[1] = (baudrate >> 8) & 0xFF;
    cmd[2] = (baudrate >> 16) & 0xFF;
    cmd[3] = (baudrate >> 24) & 0xFF;

    if (hci_send_cmd(h5, 0xFC17, cmd, 4) < 0)
        return -1;

    wait_for_event(h5, 0x0E, NULL, 0);

    /* Change local UART speed */
    usleep(50000);  /* Wait for chip to switch */

    tcgetattr(h5->uart_fd, &ti);
    cfsetospeed(&ti, uart_speed_to_baud(baudrate));
    cfsetispeed(&ti, uart_speed_to_baud(baudrate));
    tcsetattr(h5->uart_fd, TCSANOW, &ti);

    return 0;
}

int main(int argc, char *argv[])
{
    struct h5_struct h5;
    char fw_path[256];
    char config_path[256];
    uint16_t lmp_subver;
    int initial_speed = 115200;
    int final_speed = 1500000;
    int flow_control = 0;
    int opt;

    memset(&h5, 0, sizeof(h5));

    while ((opt = getopt(argc, argv, "s:nf")) != -1) {
        switch (opt) {
        case 's':
            initial_speed = atoi(optarg);
            break;
        case 'n':
            /* No detach - run in foreground */
            break;
        case 'f':
            flow_control = 1;
            break;
        default:
            fprintf(stderr, "Usage: %s [-s speed] [-n] [-f] device\n", argv[0]);
            return 1;
        }
    }

    if (optind >= argc) {
        fprintf(stderr, "Device not specified\n");
        return 1;
    }

    /* Initialize UART */
    h5.uart_fd = init_uart(argv[optind], initial_speed);
    if (h5.uart_fd < 0)
        return 1;

    h5.state = H5_INITIALIZED;

    /* Send HCI reset */
    printf("Sending HCI reset...\n");
    if (hci_send_cmd(&h5, HCI_OP_RESET, NULL, 0) < 0) {
        fprintf(stderr, "Failed to send HCI reset\n");
        return 1;
    }

    wait_for_event(&h5, 0x0E, NULL, 0);
    sleep(1);

    /* Read local version */
    if (rtl_read_local_version(&h5, &lmp_subver) < 0) {
        fprintf(stderr, "Failed to read local version\n");
        return 1;
    }

    printf("LMP subversion: 0x%04x\n", lmp_subver);

    /* Check if firmware already loaded */
    if (lmp_subver == 0x8723) {
        printf("Firmware already loaded\n");
    } else {
        /* Load firmware */
        snprintf(fw_path, sizeof(fw_path), "%s%s.bin", 
                RTL_FIRMWARE_DIR, RTL8723D_FW_FILE);
        snprintf(config_path, sizeof(config_path), "%s%s.bin",
                RTL_FIRMWARE_DIR, RTL8723D_CONFIG);

        if (rtl_load_firmware(&h5, fw_path, config_path) < 0) {
            fprintf(stderr, "Failed to load firmware\n");
            return 1;
        }

        /* Reset again after firmware load */
        hci_send_cmd(&h5, HCI_OP_RESET, NULL, 0);
        wait_for_event(&h5, 0x0E, NULL, 0);
        sleep(1);
    }

    /* Change to high speed */
    if (initial_speed != final_speed) {
        printf("Changing baud rate to %d...\n", final_speed);
        if (rtl_set_baudrate(&h5, final_speed) < 0) {
            fprintf(stderr, "Failed to change baud rate\n");
            return 1;
        }
    }

    /* Configure SCO routing */
    uint8_t sco_cfg[] = {0x00, 0x00};  /* Route SCO over HCI */
    hci_send_cmd(&h5, 0xFC1B, sco_cfg, 2);
    wait_for_event(&h5, 0x0E, NULL, 0);

    printf("RTL8723D initialization complete\n");

    /* Keep UART open and exit */
    return 0;
}