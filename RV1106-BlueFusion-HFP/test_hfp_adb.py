#!/usr/bin/env python3
"""
Test HFP on RV1106 via ADB
Direct testing using Android Debug Bridge
"""

import subprocess
import time
import re
import sys

class RV1106ADBTester:
    def __init__(self):
        self.device_id = None
        
    def run_adb(self, command):
        """Run ADB command and return output"""
        cmd = ['adb'] + command.split()
        try:
            result = subprocess.run(cmd, capture_output=True, text=True)
            return result.stdout, result.stderr, result.returncode
        except Exception as e:
            return "", str(e), 1
    
    def check_device(self):
        """Check if RV1106 is connected via ADB"""
        stdout, stderr, code = self.run_adb("devices")
        
        if code != 0:
            print(f"❌ ADB error: {stderr}")
            return False
            
        lines = stdout.strip().split('\n')
        devices = [l for l in lines[1:] if '\tdevice' in l]
        
        if devices:
            self.device_id = devices[0].split('\t')[0]
            print(f"✅ Found device: {self.device_id}")
            return True
        
        print("❌ No devices found")
        return False
    
    def check_bluetooth_status(self):
        """Check Bluetooth status on device"""
        print("\n[2/7] Checking Bluetooth status...")
        
        # Check if Bluetooth is enabled
        stdout, _, _ = self.run_adb("shell settings get global bluetooth_on")
        bt_enabled = stdout.strip() == "1"
        
        if bt_enabled:
            print("✅ Bluetooth is enabled")
        else:
            print("❌ Bluetooth is disabled. Enabling...")
            self.run_adb("shell svc bluetooth enable")
            time.sleep(2)
        
        # Get Bluetooth info
        stdout, _, _ = self.run_adb("shell dumpsys bluetooth_manager")
        
        # Extract MAC address
        mac_match = re.search(r'mAddress: ([\w:]+)', stdout)
        if mac_match:
            print(f"   MAC Address: {mac_match.group(1)}")
        
        # Check for RTL8723D
        stdout, _, _ = self.run_adb("shell dmesg | grep -i rtl8723")
        if "rtl8723" in stdout.lower():
            print("✅ RTL8723D detected in kernel logs")
        
        return bt_enabled
    
    def check_bluealsa(self):
        """Check if BlueALSA is running"""
        print("\n[3/7] Checking BlueALSA...")
        
        stdout, _, _ = self.run_adb("shell ps -A | grep bluealsa")
        
        if "bluealsa" in stdout:
            print("✅ BlueALSA is running")
            # Get BlueALSA status
            stdout, _, _ = self.run_adb("shell bluealsa-aplay -L")
            if stdout:
                print("   Available profiles:")
                for line in stdout.split('\n')[:5]:
                    if line.strip():
                        print(f"   - {line}")
        else:
            print("❌ BlueALSA not running. Starting...")
            # Try to start BlueALSA with HFP
            self.run_adb("shell bluealsa -p hfp-hf --hfp-codec=cvsd &")
            time.sleep(2)
    
    def check_hci_interface(self):
        """Check HCI interface"""
        print("\n[4/7] Checking HCI interface...")
        
        stdout, _, _ = self.run_adb("shell hciconfig -a")
        
        if "hci0" in stdout:
            print("✅ HCI interface found")
            # Parse HCI info
            lines = stdout.split('\n')
            for line in lines[:10]:
                if any(x in line for x in ['BD Address:', 'UP', 'RUNNING']):
                    print(f"   {line.strip()}")
        else:
            print("❌ No HCI interface found")
            # Try to bring up interface
            self.run_adb("shell hciconfig hci0 up")
    
    def scan_devices(self):
        """Scan for Bluetooth devices"""
        print("\n[5/7] Scanning for devices...")
        
        # Enable scanning
        self.run_adb("shell hciconfig hci0 piscan")
        
        # Scan
        stdout, _, _ = self.run_adb("shell timeout 10 hcitool scan")
        
        devices = []
        if stdout:
            lines = stdout.split('\n')[1:]  # Skip header
            for line in lines:
                if '\t' in line:
                    addr, name = line.strip().split('\t', 1)
                    devices.append((addr, name))
                    print(f"   Found: {addr} - {name}")
        
        if not devices:
            print("   No devices found")
        
        return devices
    
    def test_hfp_connection(self, phone_mac):
        """Test HFP connection to phone"""
        print(f"\n[6/7] Testing HFP connection to {phone_mac}...")
        
        # Check pairing status
        stdout, _, _ = self.run_adb(f"shell bluetoothctl info {phone_mac}")
        
        if "Device" not in stdout:
            print("   Device not paired. Initiating pairing...")
            # Pair device
            self.run_adb(f"shell bluetoothctl pair {phone_mac}")
            time.sleep(5)
            self.run_adb(f"shell bluetoothctl trust {phone_mac}")
        
        # Connect HFP
        print("   Connecting HFP profile...")
        stdout, _, code = self.run_adb(f"shell bluetoothctl connect {phone_mac}")
        
        if code == 0:
            print("✅ Connected to device")
        else:
            print("❌ Connection failed")
            return False
        
        # Check HFP status via BlueALSA
        time.sleep(2)
        stdout, _, _ = self.run_adb("shell bluealsa-aplay -L | grep HFP")
        
        if stdout:
            print("✅ HFP profile active in BlueALSA")
            return True
        else:
            print("❌ HFP profile not active")
            return False
    
    def check_logs(self):
        """Check system logs for HFP issues"""
        print("\n[7/7] Checking logs for issues...")
        
        # Check kernel logs
        stdout, _, _ = self.run_adb("shell dmesg | grep -i 'sco\\|hfp\\|bluetooth' | tail -20")
        
        issues = []
        if "stream_rej" in stdout:
            issues.append("Packet rejection errors detected")
        if "sco.*fail" in stdout.lower():
            issues.append("SCO connection failures")
        if "codec.*fail" in stdout.lower():
            issues.append("Codec negotiation failures")
        
        if issues:
            print("⚠️  Detected issues:")
            for issue in issues:
                print(f"   - {issue}")
        else:
            print("✅ No obvious issues in logs")
        
        # Show relevant log entries
        print("\n   Recent HFP-related logs:")
        for line in stdout.split('\n')[-10:]:
            if line.strip():
                print(f"   {line}")
    
    def run_test(self, phone_mac=None):
        """Run complete HFP test"""
        print("=" * 60)
        print("RV1106 HFP Test via ADB")
        print("=" * 60)
        
        # Step 1: Check device
        print("\n[1/7] Checking ADB connection...")
        if not self.check_device():
            return
        
        # Step 2: Check Bluetooth
        self.check_bluetooth_status()
        
        # Step 3: Check BlueALSA
        self.check_bluealsa()
        
        # Step 4: Check HCI
        self.check_hci_interface()
        
        # Step 5: Scan for devices
        devices = self.scan_devices()
        
        # Step 6: Test HFP if MAC provided
        if phone_mac:
            self.test_hfp_connection(phone_mac)
        elif devices:
            print("\n📱 Found devices. Run with MAC address to test HFP:")
            print(f"   python {sys.argv[0]} <MAC_ADDRESS>")
        
        # Step 7: Check logs
        self.check_logs()
        
        print("\n" + "=" * 60)
        print("Test complete!")
        
        if not phone_mac:
            print("\n🔧 Next steps:")
            print("1. Run with your phone's MAC address to test HFP")
            print("2. Make sure phone is discoverable")
            print("3. Accept pairing request on phone")

def main():
    tester = RV1106ADBTester()
    
    if len(sys.argv) > 1:
        phone_mac = sys.argv[1]
        tester.run_test(phone_mac)
    else:
        tester.run_test()

if __name__ == "__main__":
    main()