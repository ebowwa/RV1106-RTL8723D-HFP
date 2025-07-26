#!/usr/bin/env python3
"""
Universal Device Scanner for RV1106
Scans for:
- Serial/UART devices
- Bluetooth Classic devices
- Bluetooth Low Energy (BLE) devices
"""

import subprocess
import json
import sys
import time
import re
from datetime import datetime

class DeviceScanner:
    def __init__(self):
        self.results = {
            "scan_time": datetime.now().isoformat(),
            "serial_devices": [],
            "bluetooth_classic": [],
            "bluetooth_le": []
        }
    
    def scan_serial_ports(self):
        """Scan for serial/UART devices"""
        print("=== Scanning Serial/UART Devices ===")
        
        try:
            # Check /dev/tty* devices
            result = subprocess.run(['ls', '-la', '/dev/tty*'], 
                                  capture_output=True, text=True)
            
            # Parse serial devices
            for line in result.stdout.splitlines():
                if any(x in line for x in ['ttyS', 'ttyUSB', 'ttyAMA', 'ttyACM']):
                    parts = line.split()
                    if len(parts) >= 9:
                        device = parts[-1]
                        
                        # Get more info about the device
                        device_info = {
                            "device": device,
                            "permissions": parts[0],
                            "owner": parts[2],
                            "group": parts[3]
                        }
                        
                        # Try to get baud rate if possible
                        try:
                            stty_result = subprocess.run(['stty', '-F', device],
                                                       capture_output=True, text=True)
                            if 'speed' in stty_result.stdout:
                                speed_match = re.search(r'speed (\d+)', stty_result.stdout)
                                if speed_match:
                                    device_info["baud_rate"] = speed_match.group(1)
                        except:
                            pass
                        
                        self.results["serial_devices"].append(device_info)
                        print(f"  Found: {device}")
            
            # Check for USB serial devices
            try:
                usb_result = subprocess.run(['lsusb'], capture_output=True, text=True)
                if usb_result.returncode == 0:
                    print("\nUSB Serial Adapters:")
                    for line in usb_result.stdout.splitlines():
                        if any(x in line.lower() for x in ['serial', 'uart', 'ftdi', 'pl2303', 'ch340']):
                            print(f"  {line}")
            except:
                pass
                
        except Exception as e:
            print(f"Error scanning serial ports: {e}")
    
    def scan_bluetooth_classic(self):
        """Scan for Bluetooth Classic devices"""
        print("\n=== Scanning Bluetooth Classic Devices ===")
        
        try:
            # Check if HCI interface is up
            hci_result = subprocess.run(['hciconfig'], capture_output=True, text=True)
            if 'hci0' not in hci_result.stdout:
                print("  No HCI interface found. Initializing...")
                self.initialize_bluetooth()
                time.sleep(3)
            
            # Perform classic scan
            print("  Scanning for 10 seconds...")
            scan_result = subprocess.run(['timeout', '10', 'hcitool', 'scan'],
                                       capture_output=True, text=True)
            
            if scan_result.returncode == 0:
                for line in scan_result.stdout.splitlines()[1:]:  # Skip header
                    if '\t' in line:
                        parts = line.strip().split('\t')
                        if len(parts) >= 2:
                            device = {
                                "address": parts[0],
                                "name": parts[1] if len(parts) > 1 else "Unknown",
                                "type": "classic"
                            }
                            
                            # Get more info if possible
                            info_result = subprocess.run(['hcitool', 'info', parts[0]],
                                                       capture_output=True, text=True)
                            if info_result.returncode == 0:
                                # Parse device class
                                class_match = re.search(r'Device Class: (0x\w+)', info_result.stdout)
                                if class_match:
                                    device["class"] = class_match.group(1)
                                
                                # Parse manufacturer
                                mfg_match = re.search(r'Manufacturer: (.+)', info_result.stdout)
                                if mfg_match:
                                    device["manufacturer"] = mfg_match.group(1)
                            
                            self.results["bluetooth_classic"].append(device)
                            print(f"  Found: {device['address']} - {device['name']}")
            else:
                print("  No devices found or scan failed")
                
        except Exception as e:
            print(f"Error scanning Bluetooth Classic: {e}")
    
    def scan_bluetooth_le(self):
        """Scan for Bluetooth Low Energy devices"""
        print("\n=== Scanning Bluetooth LE Devices ===")
        
        try:
            # Check if LE is supported
            le_check = subprocess.run(['hciconfig', 'hci0', 'lestates'],
                                    capture_output=True, text=True)
            
            if 'LE States' not in le_check.stdout:
                print("  BLE not supported or not initialized")
                return
            
            # Enable LE scanning
            subprocess.run(['hciconfig', 'hci0', 'leadv'], capture_output=True)
            
            # Perform LE scan
            print("  Scanning for 10 seconds...")
            lescan_result = subprocess.run(['timeout', '10', 'hcitool', 'lescan'],
                                         capture_output=True, text=True)
            
            # Parse results
            seen_devices = set()
            if lescan_result.stdout:
                for line in lescan_result.stdout.splitlines()[1:]:  # Skip header
                    parts = line.strip().split(' ', 1)
                    if len(parts) >= 1:
                        address = parts[0]
                        if address and address not in seen_devices:
                            seen_devices.add(address)
                            device = {
                                "address": address,
                                "name": parts[1] if len(parts) > 1 else "Unknown",
                                "type": "ble"
                            }
                            
                            # Try to get RSSI
                            rssi_result = subprocess.run(['hcitool', 'rssi', address],
                                                       capture_output=True, text=True)
                            if 'RSSI' in rssi_result.stdout:
                                rssi_match = re.search(r'RSSI return value: (-?\d+)', rssi_result.stdout)
                                if rssi_match:
                                    device["rssi"] = int(rssi_match.group(1))
                            
                            self.results["bluetooth_le"].append(device)
                            print(f"  Found: {device['address']} - {device['name']}")
            
            if not seen_devices:
                print("  No BLE devices found")
                
        except Exception as e:
            print(f"Error scanning Bluetooth LE: {e}")
    
    def initialize_bluetooth(self):
        """Initialize Bluetooth hardware"""
        print("  Attempting to initialize Bluetooth...")
        
        # Try different initialization methods
        init_commands = [
            ['hciattach', '/dev/ttyS5', 'any', '1500000', 'flow'],
            ['hciattach', '/dev/ttyS5', 'any', '115200', 'flow'],
            ['/tmp/rtk_hciattach', '-s', '115200', '/dev/ttyS5', 'rtk_h5'],
            ['/userdata/rtkhci', '-n', '-s', '115200', '/dev/ttyS5', 'rtk_h5']
        ]
        
        for cmd in init_commands:
            try:
                if cmd[0].startswith('/') and not subprocess.run(['test', '-f', cmd[0]], capture_output=True).returncode == 0:
                    continue
                    
                print(f"  Trying: {' '.join(cmd)}")
                subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                time.sleep(5)
                
                # Check if interface came up
                hci_check = subprocess.run(['hciconfig'], capture_output=True, text=True)
                if 'hci0' in hci_check.stdout:
                    subprocess.run(['hciconfig', 'hci0', 'up'], capture_output=True)
                    print("  Bluetooth initialized successfully")
                    return True
            except:
                pass
        
        print("  Failed to initialize Bluetooth")
        return False
    
    def scan_all(self):
        """Perform all scans"""
        self.scan_serial_ports()
        self.scan_bluetooth_classic()
        self.scan_bluetooth_le()
        
        # Save results
        self.save_results()
        self.print_summary()
    
    def save_results(self):
        """Save scan results to JSON file"""
        filename = f"device_scan_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(filename, 'w') as f:
            json.dump(self.results, f, indent=2)
        print(f"\nResults saved to: {filename}")
    
    def print_summary(self):
        """Print scan summary"""
        print("\n=== SCAN SUMMARY ===")
        print(f"Serial devices found: {len(self.results['serial_devices'])}")
        print(f"Bluetooth Classic devices found: {len(self.results['bluetooth_classic'])}")
        print(f"Bluetooth LE devices found: {len(self.results['bluetooth_le'])}")


if __name__ == "__main__":
    scanner = DeviceScanner()
    
    if len(sys.argv) > 1:
        if sys.argv[1] == "serial":
            scanner.scan_serial_ports()
        elif sys.argv[1] == "classic":
            scanner.scan_bluetooth_classic()
        elif sys.argv[1] == "ble":
            scanner.scan_bluetooth_le()
        else:
            print("Usage: device_scanner.py [serial|classic|ble|all]")
    else:
        scanner.scan_all()