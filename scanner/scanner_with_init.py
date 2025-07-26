#!/usr/bin/env python3
"""
Scanner with integrated RTL8723D initialization
"""

import subprocess
import time
import os
import signal
import sys

class RTL8723DScanner:
    def __init__(self):
        self.hci_process = None
        self.initialized = False
        
    def cleanup(self):
        """Kill any existing Bluetooth processes"""
        print("Cleaning up...")
        subprocess.run(['killall', '-q', 'rtkhci', 'rtk_hciattach', 'hciattach'], stderr=subprocess.DEVNULL)
        time.sleep(2)
        
    def init_with_high_baud(self):
        """Initialize at 1500000 baud (known to work)"""
        print("Initializing at 1500000 baud...")
        
        # First, standard hciattach at high speed
        self.hci_process = subprocess.Popen(
            ['hciattach', '-s', '1500000', '/dev/ttyS5', 'any', '1500000', 'flow'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        time.sleep(5)
        
        # Check if interface exists
        result = subprocess.run(['hciconfig', 'hci0'], capture_output=True, text=True)
        if 'hci0' in result.stdout:
            print("✓ HCI interface created")
            
            # Now try rtk_hciattach to load firmware
            if os.path.exists('/tmp/rtk_hciattach'):
                print("Loading firmware with rtk_hciattach...")
                
                # Kill the standard hciattach
                if self.hci_process:
                    self.hci_process.terminate()
                    time.sleep(2)
                
                # Run rtk_hciattach
                rtk_process = subprocess.Popen(
                    ['/tmp/rtk_hciattach', '-s', '1500000', '/dev/ttyS5', 'rtk_h5'],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True
                )
                
                # Monitor output
                for i in range(20):
                    line = rtk_process.stdout.readline()
                    if line:
                        print(f"  {line.strip()}")
                        if "Realtek Bluetooth init complete" in line:
                            print("✓ Firmware loaded!")
                            self.initialized = True
                            break
                    time.sleep(0.5)
                
                # Give it more time
                time.sleep(5)
                
                # Check MAC address
                result = subprocess.run(['hciconfig', 'hci0'], capture_output=True, text=True)
                if "BD Address:" in result.stdout and "00:00:00:00:00:00" not in result.stdout:
                    print(f"✓ Got MAC address: {result.stdout}")
                    self.initialized = True
                else:
                    print("✗ No valid MAC address")
                    
            return self.initialized
        
        return False
    
    def scan_devices(self):
        """Scan for all devices"""
        print("\n=== Device Scan Results ===")
        
        # Serial devices
        print("\n[Serial Devices]")
        result = subprocess.run(['ls', '-la', '/dev/ttyS*'], capture_output=True, text=True)
        for line in result.stdout.splitlines():
            if '/dev/ttyS' in line:
                print(f"  {line.split()[-1]}")
        
        # Bluetooth status
        print("\n[Bluetooth Status]")
        subprocess.run(['hciconfig', '-a'])
        
        if self.initialized:
            # Classic scan
            print("\n[Bluetooth Classic Scan]")
            print("Scanning for 10 seconds...")
            scan_proc = subprocess.Popen(['hcitool', 'scan'], stdout=subprocess.PIPE, text=True)
            try:
                output, _ = scan_proc.communicate(timeout=10)
                print(output)
            except subprocess.TimeoutExpired:
                scan_proc.kill()
                
            # LE scan
            print("\n[Bluetooth LE Scan]")
            print("Scanning for 10 seconds...")
            subprocess.run(['hciconfig', 'hci0', 'leadv'], capture_output=True)
            
            lescan_proc = subprocess.Popen(['hcitool', 'lescan'], stdout=subprocess.PIPE, text=True)
            try:
                time.sleep(10)
                lescan_proc.terminate()
                output, _ = lescan_proc.communicate(timeout=1)
                print(output)
            except:
                lescan_proc.kill()
        else:
            print("Bluetooth not initialized - cannot scan")
    
    def run(self):
        """Main execution"""
        self.cleanup()
        
        # Try different init methods
        if not self.init_with_high_baud():
            print("\nTrying alternative initialization...")
            
            # Try with rtkhci
            if os.path.exists('/userdata/rtkhci'):
                print("Using rtkhci...")
                self.cleanup()
                
                rtkhci_proc = subprocess.Popen(
                    ['sh', '-c', 'cd /userdata && ./rtkhci -n -s 115200 /dev/ttyS5 rtk_h5'],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True
                )
                
                time.sleep(10)
                
                # Check if it worked
                result = subprocess.run(['hciconfig', 'hci0'], capture_output=True, text=True)
                if 'hci0' in result.stdout:
                    self.initialized = True
        
        # Run scan regardless
        self.scan_devices()

def signal_handler(sig, frame):
    print("\nExiting...")
    sys.exit(0)

if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal_handler)
    
    scanner = RTL8723DScanner()
    scanner.run()