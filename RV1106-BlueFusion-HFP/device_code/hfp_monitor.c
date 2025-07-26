/*
 * HFP Connection Monitor for RV1106
 * Real-time monitoring and auto-recovery
 * 
 * Compile: arm-linux-gnueabihf-gcc -O2 -o hfp_monitor hfp_monitor.c -lbluetooth
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <syslog.h>
#include <errno.h>
#include <sys/socket.h>
#include <bluetooth/bluetooth.h>
#include <bluetooth/hci.h>
#include <bluetooth/hci_lib.h>
#include <bluetooth/rfcomm.h>
#include <bluetooth/sco.h>

#define MAX_CONNECTIONS 5
#define CHECK_INTERVAL  5  /* seconds */
#define LOG_FILE       "/var/log/hfp_monitor.log"

struct connection_info {
    bdaddr_t addr;
    uint16_t handle;
    uint8_t  type;      /* ACL or SCO */
    uint8_t  link_quality;
    int8_t   rssi;
    time_t   last_seen;
    int      failures;
};

struct monitor_stats {
    int total_connections;
    int sco_connections;
    int failures_recovered;
    int packets_lost;
    time_t start_time;
};

static volatile int running = 1;
static struct connection_info connections[MAX_CONNECTIONS];
static struct monitor_stats stats = {0};
static int hci_dev = -1;

static void signal_handler(int sig)
{
    running = 0;
}

static void log_message(const char *fmt, ...)
{
    va_list args;
    char buf[256];
    time_t now;
    struct tm *tm;
    
    time(&now);
    tm = localtime(&now);
    
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    
    printf("[%02d:%02d:%02d] %s\n", tm->tm_hour, tm->tm_min, tm->tm_sec, buf);
    syslog(LOG_INFO, "%s", buf);
}

static int check_hci_status(void)
{
    struct hci_dev_info di;
    
    if (hci_devinfo(hci_dev, &di) < 0) {
        return -1;
    }
    
    if (!(hci_test_bit(HCI_UP, &di.flags))) {
        log_message("HCI device is down");
        return -1;
    }
    
    if (!(hci_test_bit(HCI_RUNNING, &di.flags))) {
        log_message("HCI device not running");
        return -1;
    }
    
    return 0;
}

static int get_connection_list(void)
{
    struct hci_conn_list_req *cl;
    struct hci_conn_info *ci;
    int i, n = 0;
    
    cl = malloc(10 * sizeof(*ci) + sizeof(*cl));
    if (!cl) {
        return -1;
    }
    
    cl->dev_id = hci_dev;
    cl->conn_num = 10;
    ci = cl->conn_info;
    
    if (ioctl(hci_dev, HCIGETCONNLIST, cl) < 0) {
        free(cl);
        return -1;
    }
    
    /* Update connection list */
    memset(connections, 0, sizeof(connections));
    
    for (i = 0; i < cl->conn_num && i < MAX_CONNECTIONS; i++) {
        bacpy(&connections[n].addr, &ci[i].bdaddr);
        connections[n].handle = ci[i].handle;
        connections[n].type = ci[i].type;
        connections[n].last_seen = time(NULL);
        n++;
    }
    
    free(cl);
    return n;
}

static int get_link_quality(uint16_t handle, uint8_t *lq)
{
    struct hci_request rq;
    read_link_quality_cp cp;
    read_link_quality_rp rp;
    
    memset(&cp, 0, sizeof(cp));
    cp.handle = handle;
    
    memset(&rq, 0, sizeof(rq));
    rq.ogf = OGF_STATUS_PARAM;
    rq.ocf = OCF_READ_LINK_QUALITY;
    rq.cparam = &cp;
    rq.clen = sizeof(cp);
    rq.rparam = &rp;
    rq.rlen = sizeof(rp);
    
    if (hci_send_req(hci_dev, &rq, 1000) < 0) {
        return -1;
    }
    
    if (rp.status) {
        return -1;
    }
    
    *lq = rp.link_quality;
    return 0;
}

static int get_rssi(uint16_t handle, int8_t *rssi)
{
    struct hci_request rq;
    read_rssi_cp cp;
    read_rssi_rp rp;
    
    memset(&cp, 0, sizeof(cp));
    cp.handle = handle;
    
    memset(&rq, 0, sizeof(rq));
    rq.ogf = OGF_STATUS_PARAM;
    rq.ocf = OCF_READ_RSSI;
    rq.cparam = &cp;
    rq.clen = sizeof(cp);
    rq.rparam = &rp;
    rq.rlen = sizeof(rp);
    
    if (hci_send_req(hci_dev, &rq, 1000) < 0) {
        return -1;
    }
    
    if (rp.status) {
        return -1;
    }
    
    *rssi = rp.rssi;
    return 0;
}

static void monitor_connections(void)
{
    int i, n;
    char addr_str[18];
    
    n = get_connection_list();
    if (n < 0) {
        log_message("Failed to get connection list");
        return;
    }
    
    stats.total_connections = n;
    stats.sco_connections = 0;
    
    for (i = 0; i < n; i++) {
        ba2str(&connections[i].addr, addr_str);
        
        /* Get link quality */
        if (get_link_quality(connections[i].handle, &connections[i].link_quality) < 0) {
            connections[i].link_quality = 0;
        }
        
        /* Get RSSI */
        if (get_rssi(connections[i].handle, &connections[i].rssi) < 0) {
            connections[i].rssi = -100;
        }
        
        /* Count SCO connections */
        if (connections[i].type == SCO_LINK) {
            stats.sco_connections++;
        }
        
        /* Check for poor quality */
        if (connections[i].link_quality < 200 || connections[i].rssi < -80) {
            connections[i].failures++;
            log_message("Poor link quality: %s LQ=%d RSSI=%d", 
                       addr_str, connections[i].link_quality, connections[i].rssi);
            
            /* Trigger recovery if too many failures */
            if (connections[i].failures > 3) {
                log_message("Triggering recovery for %s", addr_str);
                /* Recovery actions would go here */
                connections[i].failures = 0;
                stats.failures_recovered++;
            }
        }
    }
}

static void check_bluealsa(void)
{
    FILE *fp;
    char buf[256];
    int bluealsa_running = 0;
    
    /* Check if BlueALSA is running */
    fp = popen("pidof bluealsa", "r");
    if (fp) {
        if (fgets(buf, sizeof(buf), fp) != NULL) {
            bluealsa_running = 1;
        }
        pclose(fp);
    }
    
    if (!bluealsa_running) {
        log_message("BlueALSA not running, restarting...");
        system("/etc/init.d/bluealsa restart");
        stats.failures_recovered++;
    }
}

static void print_statistics(void)
{
    time_t uptime = time(NULL) - stats.start_time;
    
    log_message("=== HFP Monitor Statistics ===");
    log_message("Uptime: %ld seconds", uptime);
    log_message("Total connections: %d", stats.total_connections);
    log_message("SCO connections: %d", stats.sco_connections);
    log_message("Failures recovered: %d", stats.failures_recovered);
    
    if (stats.total_connections > 0) {
        int i;
        char addr_str[18];
        
        log_message("Active connections:");
        for (i = 0; i < MAX_CONNECTIONS; i++) {
            if (bacmp(&connections[i].addr, BDADDR_ANY) != 0) {
                ba2str(&connections[i].addr, addr_str);
                log_message("  %s: Type=%s LQ=%d RSSI=%d", 
                           addr_str,
                           connections[i].type == ACL_LINK ? "ACL" : "SCO",
                           connections[i].link_quality,
                           connections[i].rssi);
            }
        }
    }
}

static int init_monitor(void)
{
    /* Open HCI device */
    hci_dev = hci_get_route(NULL);
    if (hci_dev < 0) {
        log_message("No Bluetooth device found");
        return -1;
    }
    
    hci_dev = hci_open_dev(hci_dev);
    if (hci_dev < 0) {
        log_message("Failed to open HCI device");
        return -1;
    }
    
    /* Initialize stats */
    stats.start_time = time(NULL);
    
    return 0;
}

static void cleanup(void)
{
    if (hci_dev >= 0) {
        hci_close_dev(hci_dev);
    }
}

int main(int argc, char *argv[])
{
    int daemon_mode = 0;
    int opt;
    
    while ((opt = getopt(argc, argv, "dh")) != -1) {
        switch (opt) {
        case 'd':
            daemon_mode = 1;
            break;
        case 'h':
            printf("Usage: %s [-d] [-h]\n", argv[0]);
            printf("  -d  Run as daemon\n");
            printf("  -h  Show this help\n");
            return 0;
        }
    }
    
    /* Setup signal handlers */
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    /* Open syslog */
    openlog("hfp_monitor", LOG_PID, LOG_DAEMON);
    
    /* Daemonize if requested */
    if (daemon_mode) {
        if (daemon(0, 0) < 0) {
            perror("daemon");
            return 1;
        }
    }
    
    /* Initialize monitor */
    if (init_monitor() < 0) {
        return 1;
    }
    
    log_message("HFP Monitor started");
    
    /* Main monitoring loop */
    while (running) {
        /* Check HCI status */
        if (check_hci_status() < 0) {
            log_message("HCI device error, attempting recovery...");
            system("/etc/init.d/rtl8723d-bluetooth restart");
            sleep(10);
            
            /* Reinitialize */
            cleanup();
            if (init_monitor() < 0) {
                break;
            }
            stats.failures_recovered++;
        }
        
        /* Monitor connections */
        monitor_connections();
        
        /* Check BlueALSA */
        check_bluealsa();
        
        /* Print statistics periodically */
        if (time(NULL) % 60 == 0) {
            print_statistics();
        }
        
        sleep(CHECK_INTERVAL);
    }
    
    log_message("HFP Monitor stopped");
    print_statistics();
    
    cleanup();
    closelog();
    
    return 0;
}