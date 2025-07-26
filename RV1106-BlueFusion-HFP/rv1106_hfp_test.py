#!/usr/bin/env python3
"""
Direct RV1106 HFP Testing Script
Tests HFP connection on USB-connected RV1106 with RTL8723D
"""

import asyncio
import logging
import sys
import argparse
from datetime import datetime

# Add BlueFusion to path
sys.path.insert(0, '.')

from src.rv1106_adapter import RV1106Adapter
from src.hfp_handler import HFPProtocolHandler
from src.sco_audio import SCOAudioAnalyzer

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

async def test_rv1106_hfp(phone_address: str, rkdeveloptool_path: str = "rkdeveloptool"):
    """Test HFP on RV1106 device"""
    
    print("=" * 60)
    print("RV1106 HFP Testing Tool")
    print("=" * 60)
    
    # Initialize RV1106 adapter
    adapter = RV1106Adapter(rkdeveloptool_path)
    
    # Step 1: Detect device
    print("\n[1/6] Detecting RV1106 device...")
    device = await adapter.detect_device()
    
    if not device:
        print("❌ No RV1106 device found. Please check:")
        print("   - Device is connected via USB")
        print("   - Device is in Maskrom or Loader mode")
        print("   - rkdeveloptool is installed")
        return
    
    print(f"✅ Found RV1106: {device.vid_pid} in {device.mode} mode")
    
    # Step 2: Initialize Bluetooth
    print("\n[2/6] Initializing RTL8723D Bluetooth...")
    bt_init = await adapter.initialize_bluetooth()
    
    if not bt_init:
        print("❌ Failed to initialize Bluetooth")
        return
        
    print(f"✅ Bluetooth initialized: {adapter.bt_info.mac_address}")
    
    # Step 3: Configure SCO routing
    print("\n[3/6] Configuring SCO audio routing...")
    await adapter.configure_sco_routing("hci")  # Route over USB
    print("✅ SCO routing configured for HCI (USB)")
    
    # Step 4: Start BlueALSA with HFP
    print("\n[4/6] Starting BlueALSA with HFP-HF support...")
    bluealsa_started = await adapter.start_bluealsa_hfp()
    
    if not bluealsa_started:
        print("❌ Failed to start BlueALSA")
        return
        
    print("✅ BlueALSA started with HFP-HF profile")
    
    # Step 5: Test HFP connection
    print(f"\n[5/6] Testing HFP connection to {phone_address}...")
    print("Please ensure:")
    print("   - Phone Bluetooth is ON")
    print("   - Phone is discoverable")
    print("   - Previous pairings are removed")
    
    await asyncio.sleep(3)
    
    test_result = await adapter.test_hfp_connection(phone_address)
    
    # Step 6: Analyze results
    print("\n[6/6] Analyzing connection...")
    
    print("\n📊 Connection Steps:")
    for step in test_result['steps']:
        status = "✅" if step['success'] else "❌"
        print(f"   {status} {step['step']}")
        if not step['success'] and 'output' in step:
            print(f"      Output: {step['output'][:200]}...")
    
    if 'diagnostics' in test_result and 'issues' in test_result['diagnostics']:
        print("\n⚠️  Detected Issues:")
        for issue in test_result['diagnostics']['issues']:
            print(f"   - {issue}")
    
    # Show relevant logs
    if 'diagnostics' in test_result and 'logs' in test_result['diagnostics']:
        logs = test_result['diagnostics']['logs']
        
        # Check for specific HFP errors
        print("\n📋 HFP-related log entries:")
        
        for log_type, entries in logs.items():
            relevant_entries = [
                entry for entry in entries 
                if any(keyword in entry.lower() for keyword in ['hfp', 'sco', 'at+', 'codec', 'cvsd', 'msbc'])
            ]
            
            if relevant_entries:
                print(f"\n   From {log_type}:")
                for entry in relevant_entries[-5:]:  # Last 5 relevant entries
                    if entry.strip():
                        print(f"      {entry}")
    
    # Summary
    print("\n" + "=" * 60)
    if test_result['success']:
        print("✅ HFP CONNECTION SUCCESSFUL!")
        print("   The device can now handle phone calls")
    else:
        print("❌ HFP CONNECTION FAILED")
        print("\n🔧 Troubleshooting suggestions:")
        print("   1. Try with CVSD codec only: bluealsa -p hfp-hf --hfp-codec=cvsd")
        print("   2. Check kernel SCO support: cat /sys/module/bluetooth/parameters/disable_esco")
        print("   3. Try different phone (iOS vs Android)")
        print("   4. Use ofono instead of BlueALSA")
    
    # Cleanup
    await adapter.cleanup()

async def monitor_mode(rkdeveloptool_path: str = "rkdeveloptool"):
    """Continuous monitoring mode"""
    adapter = RV1106Adapter(rkdeveloptool_path)
    
    print("Starting HFP monitoring mode...")
    print("Press Ctrl+C to stop\n")
    
    device = await adapter.detect_device()
    if not device:
        print("No device found")
        return
    
    await adapter.initialize_bluetooth()
    
    try:
        while True:
            status = await adapter.monitor_hfp_connection()
            
            # Clear screen
            print("\033[2J\033[H")
            print(f"RV1106 HFP Monitor - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            print("=" * 60)
            
            if 'issues' in status and status['issues']:
                print("\n⚠️  Active Issues:")
                for issue in status['issues']:
                    print(f"   - {issue}")
            else:
                print("\n✅ No issues detected")
            
            print("\nPress Ctrl+C to stop monitoring...")
            
            await asyncio.sleep(5)
            
    except KeyboardInterrupt:
        print("\nStopping monitor...")
    finally:
        await adapter.cleanup()

def main():
    parser = argparse.ArgumentParser(description="Test HFP on RV1106 with RTL8723D")
    parser.add_argument("phone_address", nargs='?', help="Phone Bluetooth MAC address (XX:XX:XX:XX:XX:XX)")
    parser.add_argument("--monitor", action="store_true", help="Run in monitoring mode")
    parser.add_argument("--rkdeveloptool", default="rkdeveloptool", help="Path to rkdeveloptool")
    
    args = parser.parse_args()
    
    if args.monitor:
        asyncio.run(monitor_mode(args.rkdeveloptool))
    elif args.phone_address:
        # Validate MAC address format
        if not all(len(part) == 2 for part in args.phone_address.split(':')):
            print("Invalid MAC address format. Use XX:XX:XX:XX:XX:XX")
            sys.exit(1)
        
        asyncio.run(test_rv1106_hfp(args.phone_address, args.rkdeveloptool))
    else:
        parser.print_help()
        print("\nExamples:")
        print("  Test HFP:     python test_rv1106_hfp.py E8:D5:2B:13:B5:AB")
        print("  Monitor mode: python test_rv1106_hfp.py --monitor")

if __name__ == "__main__":
    main()