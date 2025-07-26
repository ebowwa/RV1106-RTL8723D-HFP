#!/usr/bin/env python3
"""
Direct USB device test for RV1106
Tests connection without rkdeveloptool
"""

import subprocess
import re
import json

def find_rockchip_device():
    """Find connected Rockchip device via system_profiler"""
    try:
        # Get USB device info
        result = subprocess.run(
            ['system_profiler', 'SPUSBDataType', '-json'],
            capture_output=True,
            text=True
        )
        
        if result.returncode != 0:
            print(f"Error running system_profiler: {result.stderr}")
            return None
            
        # Parse JSON output
        data = json.loads(result.stdout)
        
        # Search for Rockchip devices
        for item in data.get('SPUSBDataType', []):
            devices = item.get('_items', [])
            for device in devices:
                if 'rockchip' in str(device).lower() or '0x2207' in str(device):
                    return {
                        'name': device.get('_name', 'Unknown'),
                        'vendor_id': device.get('vendor_id', ''),
                        'product_id': device.get('product_id', ''),
                        'serial': device.get('serial_num', ''),
                        'manufacturer': device.get('manufacturer', ''),
                        'location_id': device.get('location_id', '')
                    }
        
        return None
        
    except Exception as e:
        print(f"Error finding device: {e}")
        return None

def check_bluetooth_status():
    """Check if Bluetooth is available on the system"""
    try:
        # Check Bluetooth status on macOS
        result = subprocess.run(
            ['system_profiler', 'SPBluetoothDataType'],
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            if 'Bluetooth:' in result.stdout:
                print("\n✅ System Bluetooth is available")
                # Extract some info
                lines = result.stdout.split('\n')
                for line in lines[:10]:
                    if 'Address:' in line or 'Bluetooth Low Energy Supported:' in line:
                        print(f"   {line.strip()}")
                return True
        
        return False
        
    except Exception as e:
        print(f"Error checking Bluetooth: {e}")
        return False

def main():
    print("=" * 60)
    print("RV1106 USB Device Test")
    print("=" * 60)
    
    # Find Rockchip device
    print("\n[1/2] Looking for Rockchip RV1106 device...")
    device = find_rockchip_device()
    
    if device:
        print("✅ Found Rockchip device!")
        print(f"   Name: {device['name']}")
        print(f"   Vendor ID: {device['vendor_id']}")
        print(f"   Product ID: {device['product_id']}")
        print(f"   Serial: {device['serial']}")
        print(f"   Manufacturer: {device['manufacturer']}")
        print(f"   Location ID: {device['location_id']}")
    else:
        print("❌ No Rockchip device found")
        print("   Please check:")
        print("   - Device is connected via USB-C")
        print("   - Device is powered on")
        print("   - USB cable supports data transfer")
    
    # Check Bluetooth
    print("\n[2/2] Checking Bluetooth availability...")
    check_bluetooth_status()
    
    print("\n" + "=" * 60)
    print("Next Steps:")
    print("1. Install rkdeveloptool: brew install --cask rkdeveloptool")
    print("2. Or use adb if device supports it: brew install android-platform-tools")
    print("3. Check if device appears as serial port: ls /dev/tty.*")
    print("4. Try direct serial communication with the RTL8723D module")

if __name__ == "__main__":
    main()