"""
Classic Bluetooth Adapter for BlueFusion
Handles Classic Bluetooth connections and profile management
"""

import asyncio
import time
import logging
from typing import List, Dict, Optional, Any
from dataclasses import dataclass
import subprocess
import socket
import struct

try:
    import bluetooth
except ImportError:
    bluetooth = None
    logging.warning("PyBluez not installed. Classic Bluetooth features will be limited.")

@dataclass
class ClassicDevice:
    """Represents a Classic Bluetooth device"""
    address: str
    name: str
    device_class: int
    rssi: Optional[int] = None
    profiles: List[str] = None
    
    def __post_init__(self):
        if self.profiles is None:
            self.profiles = self._detect_profiles()
    
    def _detect_profiles(self) -> List[str]:
        """Detect supported profiles from device class"""
        profiles = []
        if self.device_class & 0x200000:  # Audio device
            profiles.extend(['HFP', 'HSP', 'A2DP'])
        if self.device_class & 0x100000:  # Computer device
            profiles.append('PAN')
        if self.device_class & 0x80000:   # Phone device
            profiles.extend(['HFP', 'HSP', 'PBAP'])
        return profiles

@dataclass
class HFPConnection:
    """Represents an HFP connection"""
    id: str
    device: ClassicDevice
    rfcomm_socket: Optional[socket.socket] = None
    sco_socket: Optional[socket.socket] = None
    state: str = "DISCONNECTED"
    codec: str = "CVSD"
    features: Dict[str, bool] = None

class ClassicBluetoothAdapter:
    """Classic Bluetooth implementation for BlueFusion"""
    
    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.hfp_connections: Dict[str, HFPConnection] = {}
        self.running = False
        
    async def scan_classic_devices(self, duration: int = 10) -> List[ClassicDevice]:
        """Scan for Classic Bluetooth devices"""
        self.logger.info(f"Scanning for Classic Bluetooth devices for {duration} seconds...")
        
        if bluetooth is None:
            # Fallback to hcitool if PyBluez not available
            return await self._scan_with_hcitool(duration)
        
        try:
            devices = bluetooth.discover_devices(
                duration=duration,
                lookup_names=True,
                lookup_class=True
            )
            
            classic_devices = []
            for addr, name, device_class in devices:
                device = ClassicDevice(
                    address=addr,
                    name=name or "Unknown",
                    device_class=device_class
                )
                classic_devices.append(device)
                
            self.logger.info(f"Found {len(classic_devices)} Classic Bluetooth devices")
            return classic_devices
            
        except Exception as e:
            self.logger.error(f"Error scanning Classic devices: {e}")
            return []
    
    async def _scan_with_hcitool(self, duration: int) -> List[ClassicDevice]:
        """Fallback scanning using hcitool"""
        try:
            # Run hcitool scan
            process = await asyncio.create_subprocess_exec(
                'hcitool', 'scan', '--length', str(duration),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            stdout, stderr = await process.communicate()
            
            devices = []
            for line in stdout.decode().split('\n')[1:]:  # Skip header
                if line.strip():
                    parts = line.strip().split('\t')
                    if len(parts) >= 2:
                        addr, name = parts[0], parts[1]
                        devices.append(ClassicDevice(
                            address=addr,
                            name=name,
                            device_class=0  # Can't get class from hcitool scan
                        ))
            
            return devices
            
        except Exception as e:
            self.logger.error(f"Error with hcitool scan: {e}")
            return []
    
    async def connect_hfp(self, address: str) -> Optional[HFPConnection]:
        """Connect to an HFP device"""
        self.logger.info(f"Connecting to HFP device: {address}")
        
        try:
            # Find device
            devices = await self.scan_classic_devices(5)
            device = next((d for d in devices if d.address == address), None)
            
            if not device:
                device = ClassicDevice(address=address, name="Unknown", device_class=0)
            
            # Create connection object
            connection = HFPConnection(
                id=f"hfp_{address.replace(':', '')}_{int(time.time())}",
                device=device,
                features={}
            )
            
            # Connect RFCOMM for control channel
            if bluetooth:
                rfcomm_socket = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
                rfcomm_socket.connect((address, 1))  # HFP usually on channel 1
                connection.rfcomm_socket = rfcomm_socket
                connection.state = "RFCOMM_CONNECTED"
            
            # Store connection
            self.hfp_connections[connection.id] = connection
            
            self.logger.info(f"HFP connection established: {connection.id}")
            return connection
            
        except Exception as e:
            self.logger.error(f"Failed to connect HFP: {e}")
            return None
    
    async def connect_sco(self, connection_id: str) -> bool:
        """Establish SCO audio connection"""
        connection = self.hfp_connections.get(connection_id)
        if not connection:
            return False
        
        try:
            if bluetooth:
                sco_socket = bluetooth.BluetoothSocket(bluetooth.SCO)
                sco_socket.connect((connection.device.address, ))
                connection.sco_socket = sco_socket
                connection.state = "SCO_CONNECTED"
                return True
            else:
                # Fallback to using hcitool
                result = await self._connect_sco_hcitool(connection.device.address)
                if result:
                    connection.state = "SCO_CONNECTED"
                return result
                
        except Exception as e:
            self.logger.error(f"Failed to connect SCO: {e}")
            return False
    
    async def _connect_sco_hcitool(self, address: str) -> bool:
        """Connect SCO using hcitool"""
        try:
            # Get connection handle
            process = await asyncio.create_subprocess_exec(
                'hcitool', 'con',
                stdout=asyncio.subprocess.PIPE
            )
            stdout, _ = await process.communicate()
            
            # Parse connection handle
            handle = None
            for line in stdout.decode().split('\n'):
                if address in line and 'handle' in line:
                    parts = line.split()
                    handle_idx = parts.index('handle') + 1
                    if handle_idx < len(parts):
                        handle = parts[handle_idx]
                        break
            
            if handle:
                # Setup SCO connection
                process = await asyncio.create_subprocess_exec(
                    'hcitool', 'sco', handle
                )
                await process.wait()
                return process.returncode == 0
                
            return False
            
        except Exception as e:
            self.logger.error(f"Error with hcitool SCO: {e}")
            return False
    
    def get_connection_stats(self, connection_id: str) -> Dict[str, Any]:
        """Get statistics for a connection"""
        connection = self.hfp_connections.get(connection_id)
        if not connection:
            return {}
        
        stats = {
            'id': connection.id,
            'device': {
                'address': connection.device.address,
                'name': connection.device.name,
                'profiles': connection.device.profiles
            },
            'state': connection.state,
            'codec': connection.codec,
            'features': connection.features,
            'rfcomm_connected': connection.rfcomm_socket is not None,
            'sco_connected': connection.sco_socket is not None
        }
        
        return stats
    
    def has_active_sco(self) -> bool:
        """Check if any SCO connection is active"""
        return any(
            conn.sco_socket is not None 
            for conn in self.hfp_connections.values()
        )
    
    async def disconnect(self, connection_id: str):
        """Disconnect a connection"""
        connection = self.hfp_connections.get(connection_id)
        if not connection:
            return
        
        try:
            if connection.sco_socket:
                connection.sco_socket.close()
            if connection.rfcomm_socket:
                connection.rfcomm_socket.close()
            
            del self.hfp_connections[connection_id]
            self.logger.info(f"Disconnected: {connection_id}")
            
        except Exception as e:
            self.logger.error(f"Error disconnecting: {e}")