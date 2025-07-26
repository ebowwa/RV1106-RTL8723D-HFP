"""
RV1106 Device Adapter for BlueFusion
Integrates with rkdeveloptool for direct device control via USB
"""

import asyncio
import subprocess
import logging
import re
import os
from typing import Dict, List, Optional, Tuple, Any
from dataclasses import dataclass
import json

@dataclass
class RV1106Device:
    """RV1106 device information"""
    device_id: str
    mode: str  # "Maskrom" or "Loader"
    vid_pid: str
    connected: bool = False
    
@dataclass
class RV1106BluetoothInfo:
    """Bluetooth information from RV1106"""
    hci_device: str
    mac_address: str
    rtl_version: str
    firmware_loaded: bool
    
class RV1106Adapter:
    """Control RV1106 device with RTL8723D Bluetooth via rkdeveloptool"""
    
    def __init__(self, rkdeveloptool_path: str = "rkdeveloptool"):
        self.logger = logging.getLogger(__name__)
        self.rkdeveloptool = rkdeveloptool_path
        self.device: Optional[RV1106Device] = None
        self.bt_info: Optional[RV1106BluetoothInfo] = None
        self.shell_process: Optional[asyncio.subprocess.Process] = None
        
    async def detect_device(self) -> Optional[RV1106Device]:
        """Detect connected RV1106 device"""
        try:
            result = await self._run_rkdeveloptool("ld")
            
            if "No devices" in result:
                self.logger.info("No RV1106 device detected")
                return None
            
            # Parse device info
            # Format: DevNo=1	Vid=0x2207,Pid=0x110a,LocationID=101	Maskrom
            match = re.search(r'DevNo=(\d+)\s+Vid=(0x\w+),Pid=(0x\w+).*\s+(\w+)$', result)
            if match:
                self.device = RV1106Device(
                    device_id=match.group(1),
                    vid_pid=f"{match.group(2)}:{match.group(3)}",
                    mode=match.group(4),
                    connected=True
                )
                self.logger.info(f"Detected RV1106: {self.device}")
                return self.device
                
        except Exception as e:
            self.logger.error(f"Failed to detect device: {e}")
            return None
    
    async def _run_rkdeveloptool(self, *args) -> str:
        """Run rkdeveloptool command"""
        cmd = [self.rkdeveloptool] + list(args)
        
        try:
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            stdout, stderr = await process.communicate()
            
            if process.returncode != 0 and stderr:
                self.logger.error(f"rkdeveloptool error: {stderr.decode()}")
                
            return stdout.decode()
            
        except Exception as e:
            self.logger.error(f"Failed to run rkdeveloptool: {e}")
            raise
    
    async def open_shell(self) -> bool:
        """Open shell session on RV1106"""
        if not self.device:
            await self.detect_device()
            
        if not self.device:
            return False
            
        try:
            # For RV1106, we need to boot into a system first
            # This assumes the device has a bootable system
            self.logger.info("Opening shell session on RV1106")
            
            # Create a persistent shell session
            self.shell_process = await asyncio.create_subprocess_exec(
                'adb', 'shell',  # Assuming ADB is available after boot
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to open shell: {e}")
            return False
    
    async def execute_command(self, command: str) -> str:
        """Execute command on RV1106"""
        if not self.shell_process:
            if not await self.open_shell():
                raise Exception("Failed to open shell")
        
        try:
            # Send command
            self.shell_process.stdin.write(f"{command}\n".encode())
            await self.shell_process.stdin.drain()
            
            # Read response (simplified - real implementation needs better parsing)
            output = await asyncio.wait_for(
                self.shell_process.stdout.read(4096),
                timeout=5.0
            )
            
            return output.decode()
            
        except asyncio.TimeoutError:
            self.logger.warning(f"Command timeout: {command}")
            return ""
        except Exception as e:
            self.logger.error(f"Command execution failed: {e}")
            raise
    
    async def initialize_bluetooth(self) -> bool:
        """Initialize RTL8723D Bluetooth on RV1106"""
        self.logger.info("Initializing RTL8723D Bluetooth")
        
        try:
            # Check if firmware files exist
            fw_check = await self.execute_command("ls /lib/firmware/rtlbt/")
            if "rtl8723d_fw" not in fw_check:
                self.logger.error("RTL8723D firmware not found")
                return False
            
            # Kill any existing Bluetooth processes
            await self.execute_command("killall -q bluetoothd bluealsa bluealsa-aplay || true")
            
            # Initialize D-Bus
            await self.execute_command("rm -f /run/messagebus.pid")
            await self.execute_command("dbus-daemon --system --print-pid --print-address &")
            await asyncio.sleep(1)
            
            # Initialize RTL8723D with rtkhci
            self.logger.info("Starting rtkhci for RTL8723D")
            rtkhci_output = await self.execute_command(
                "cd /userdata && ./rtkhci -n -s 115200 /dev/ttyS5 rtk_h5 &"
            )
            await asyncio.sleep(3)
            
            # Bring up Bluetooth interface
            await self.execute_command("rfkill unblock bluetooth")
            await self.execute_command("hciconfig hci0 up")
            await asyncio.sleep(1)
            
            # Get Bluetooth info
            hci_info = await self.execute_command("hciconfig hci0")
            
            # Parse MAC address
            mac_match = re.search(r'BD Address: ([\w:]+)', hci_info)
            mac_address = mac_match.group(1) if mac_match else "Unknown"
            
            self.bt_info = RV1106BluetoothInfo(
                hci_device="hci0",
                mac_address=mac_address,
                rtl_version="RTL8723D",
                firmware_loaded=True
            )
            
            self.logger.info(f"Bluetooth initialized: {self.bt_info}")
            return True
            
        except Exception as e:
            self.logger.error(f"Bluetooth initialization failed: {e}")
            return False
    
    async def start_bluealsa_hfp(self) -> bool:
        """Start BlueALSA with HFP support"""
        try:
            # Start BlueZ with experimental features for HFP
            await self.execute_command(
                "/usr/libexec/bluetooth/bluetoothd --experimental --compat -n -d &"
            )
            await asyncio.sleep(2)
            
            # Add HF profile
            await self.execute_command("sdptool add HF")
            
            # Start BlueALSA with HFP-HF profile
            self.logger.info("Starting BlueALSA with HFP-HF support")
            bluealsa_cmd = "bluealsa -p a2dp-sink -p hfp-hf --hfp-codec=cvsd --dbus=org.bluealsa &"
            result = await self.execute_command(bluealsa_cmd)
            
            await asyncio.sleep(2)
            
            # Start bluealsa-aplay for audio
            await self.execute_command("bluealsa-aplay --profile-sco 00:00:00:00:00:00 &")
            
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to start BlueALSA: {e}")
            return False
    
    async def monitor_hfp_connection(self) -> Dict[str, Any]:
        """Monitor HFP connection status and logs"""
        logs = {
            'btmon': [],
            'bluealsa': [],
            'dmesg': []
        }
        
        try:
            # Get btmon output
            btmon_output = await self.execute_command("timeout 5 btmon 2>&1 || true")
            logs['btmon'] = btmon_output.split('\n')[-50:]  # Last 50 lines
            
            # Get BlueALSA logs
            bluealsa_log = await self.execute_command("cat /tmp/bluealsa.log 2>/dev/null || true")
            logs['bluealsa'] = bluealsa_log.split('\n')[-50:]
            
            # Get dmesg for Bluetooth
            dmesg = await self.execute_command("dmesg | grep -i bluetooth | tail -20")
            logs['dmesg'] = dmesg.split('\n')
            
            # Parse for HFP issues
            issues = []
            if "Too small packet for stream_rej" in btmon_output:
                issues.append("HFP packet rejection detected")
            if "SCO" in dmesg and "failed" in dmesg.lower():
                issues.append("SCO connection failure in kernel")
            
            return {
                'logs': logs,
                'issues': issues,
                'timestamp': asyncio.get_event_loop().time()
            }
            
        except Exception as e:
            self.logger.error(f"Monitoring failed: {e}")
            return {'error': str(e)}
    
    async def configure_sco_routing(self, routing: str = "hci") -> bool:
        """Configure SCO audio routing (hci or pcm)"""
        try:
            if routing == "hci":
                # Route SCO over HCI (USB)
                await self.execute_command("echo 1 > /sys/module/bluetooth/parameters/disable_esco")
                await self.execute_command("hciconfig hci0 voice 0x0060")  # CVSD
            else:
                # Route SCO over PCM (hardware codec)
                await self.execute_command("echo 0 > /sys/module/bluetooth/parameters/disable_esco")
                await self.execute_command("hciconfig hci0 voice 0x0003")  # Transparent
                
            self.logger.info(f"SCO routing set to: {routing}")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to configure SCO routing: {e}")
            return False
    
    async def test_hfp_connection(self, phone_address: str) -> Dict[str, Any]:
        """Test HFP connection with detailed diagnostics"""
        result = {
            'success': False,
            'steps': [],
            'diagnostics': {}
        }
        
        # Step 1: Connect via bluetoothctl
        self.logger.info(f"Testing HFP connection to {phone_address}")
        
        connect_cmd = f"""bluetoothctl << EOF
power on
agent on
default-agent
connect {phone_address}
EOF"""
        
        connect_result = await self.execute_command(connect_cmd)
        result['steps'].append({
            'step': 'Bluetooth Connect',
            'output': connect_result,
            'success': 'Connected: yes' in connect_result
        })
        
        # Step 2: Monitor HFP establishment
        await asyncio.sleep(5)  # Wait for HFP to establish
        
        hfp_status = await self.monitor_hfp_connection()
        result['diagnostics'] = hfp_status
        
        # Step 3: Check if SCO is established
        sco_check = await self.execute_command("hcitool con | grep SCO")
        result['steps'].append({
            'step': 'SCO Check',
            'output': sco_check,
            'success': bool(sco_check.strip())
        })
        
        # Determine overall success
        result['success'] = all(step.get('success', False) for step in result['steps'])
        
        return result
    
    async def cleanup(self):
        """Clean up resources"""
        if self.shell_process:
            self.shell_process.terminate()
            await self.shell_process.wait()
            self.shell_process = None