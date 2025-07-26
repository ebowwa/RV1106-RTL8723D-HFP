"""
Unified Bluetooth Monitor for BlueFusion
Combines BLE and Classic Bluetooth monitoring
"""

import asyncio
import logging
from typing import Dict, List, Any, Optional
from datetime import datetime
import json

# BLE imports
from .interfaces.base import BLEPacket, DeviceType
from .interfaces.macbook_ble import MacBookBLE
from .interfaces.sniffer_dongle import SnifferDongle

# Classic Bluetooth imports
from .classic import ClassicBluetoothAdapter, HFPProtocolHandler, SCOAudioAnalyzer
from .interfaces.classic_base import ClassicPacket, ClassicDevice, HFPConnection

class UnifiedBluetoothMonitor:
    """Monitor both BLE and Classic Bluetooth simultaneously"""
    
    def __init__(self, config: Dict[str, Any]):
        self.logger = logging.getLogger(__name__)
        self.config = config
        
        # BLE components
        self.ble_interface = None
        self.sniffer_dongle = None
        
        # Classic Bluetooth components
        self.classic_adapter = ClassicBluetoothAdapter()
        self.hfp_handlers: Dict[str, HFPProtocolHandler] = {}
        self.sco_analyzer = SCOAudioAnalyzer()
        
        # Monitoring state
        self.monitoring = False
        self.ble_devices: Dict[str, Any] = {}
        self.classic_devices: Dict[str, ClassicDevice] = {}
        self.statistics = {
            'ble': {
                'packets_captured': 0,
                'devices_discovered': 0,
                'last_packet': None
            },
            'classic': {
                'packets_captured': 0,
                'devices_discovered': 0,
                'hfp_connections': 0,
                'sco_connections': 0,
                'last_packet': None
            }
        }
        
    async def initialize(self):
        """Initialize all interfaces"""
        self.logger.info("Initializing Unified Bluetooth Monitor")
        
        # Initialize BLE
        if self.config.get('ble', {}).get('enabled', True):
            try:
                self.ble_interface = MacBookBLE()
                await self.ble_interface.initialize()
                self.logger.info("BLE interface initialized")
            except Exception as e:
                self.logger.error(f"Failed to initialize BLE: {e}")
        
        # Initialize sniffer if configured
        if self.config.get('sniffer', {}).get('enabled', False):
            try:
                self.sniffer_dongle = SnifferDongle(
                    device_path=self.config['sniffer'].get('device_path', '/dev/ttyUSB0')
                )
                await self.sniffer_dongle.initialize()
                self.logger.info("Sniffer dongle initialized")
            except Exception as e:
                self.logger.error(f"Failed to initialize sniffer: {e}")
        
        # Classic Bluetooth is initialized in constructor
        self.logger.info("Classic Bluetooth adapter initialized")
        
    async def start_monitoring(self):
        """Start monitoring both BLE and Classic Bluetooth"""
        self.monitoring = True
        self.logger.info("Starting unified Bluetooth monitoring")
        
        tasks = []
        
        # BLE monitoring tasks
        if self.ble_interface:
            tasks.append(self._monitor_ble_packets())
            tasks.append(self._scan_ble_devices())
        
        # Classic Bluetooth monitoring tasks
        tasks.append(self._monitor_classic_packets())
        tasks.append(self._scan_classic_devices())
        tasks.append(self._monitor_hfp_connections())
        
        # Run all monitoring tasks concurrently
        await asyncio.gather(*tasks, return_exceptions=True)
        
    async def stop_monitoring(self):
        """Stop all monitoring"""
        self.monitoring = False
        self.logger.info("Stopping unified Bluetooth monitoring")
        
    async def _monitor_ble_packets(self):
        """Monitor BLE packets"""
        while self.monitoring:
            try:
                if self.ble_interface:
                    async for packet in self.ble_interface.monitor_packets():
                        if not self.monitoring:
                            break
                        
                        self.statistics['ble']['packets_captured'] += 1
                        self.statistics['ble']['last_packet'] = packet.timestamp
                        
                        # Process packet
                        await self._process_ble_packet(packet)
                        
            except Exception as e:
                self.logger.error(f"BLE monitoring error: {e}")
                await asyncio.sleep(1)
    
    async def _monitor_classic_packets(self):
        """Monitor Classic Bluetooth packets"""
        while self.monitoring:
            try:
                # In a real implementation, this would capture HCI packets
                # For now, simulate with periodic device scanning
                await asyncio.sleep(5)
                
            except Exception as e:
                self.logger.error(f"Classic monitoring error: {e}")
                await asyncio.sleep(1)
    
    async def _scan_ble_devices(self):
        """Periodically scan for BLE devices"""
        while self.monitoring:
            try:
                if self.ble_interface:
                    devices = await self.ble_interface.scan_devices(duration=5)
                    
                    for device in devices:
                        self.ble_devices[device.address] = {
                            'device': device,
                            'last_seen': datetime.now(),
                            'rssi_history': []
                        }
                    
                    self.statistics['ble']['devices_discovered'] = len(self.ble_devices)
                
                await asyncio.sleep(30)  # Scan every 30 seconds
                
            except Exception as e:
                self.logger.error(f"BLE scan error: {e}")
                await asyncio.sleep(5)
    
    async def _scan_classic_devices(self):
        """Periodically scan for Classic Bluetooth devices"""
        while self.monitoring:
            try:
                devices = await self.classic_adapter.scan_classic_devices(duration=10)
                
                for device in devices:
                    self.classic_devices[device.address] = device
                    
                    # Check if device supports HFP
                    if 'HFP' in device.profiles and device.address not in self.hfp_handlers:
                        self.hfp_handlers[device.address] = HFPProtocolHandler()
                
                self.statistics['classic']['devices_discovered'] = len(self.classic_devices)
                
                await asyncio.sleep(60)  # Scan every minute
                
            except Exception as e:
                self.logger.error(f"Classic scan error: {e}")
                await asyncio.sleep(10)
    
    async def _monitor_hfp_connections(self):
        """Monitor HFP connection attempts and issues"""
        while self.monitoring:
            try:
                # Check for devices that might need HFP connection
                for address, device in self.classic_devices.items():
                    if 'HFP' in device.profiles and address in self.hfp_handlers:
                        handler = self.hfp_handlers[address]
                        
                        # Analyze any failures
                        if handler.state.value == "DISCONNECTED" and len(handler.at_command_flow) > 0:
                            analysis = handler.analyze_failure()
                            if analysis['likely_issues']:
                                self.logger.warning(f"HFP issues detected for {address}: {analysis['likely_issues']}")
                
                await asyncio.sleep(5)
                
            except Exception as e:
                self.logger.error(f"HFP monitoring error: {e}")
                await asyncio.sleep(5)
    
    async def _process_ble_packet(self, packet: BLEPacket):
        """Process BLE packet"""
        # Update device info
        if packet.address in self.ble_devices:
            device_info = self.ble_devices[packet.address]
            device_info['rssi_history'].append((packet.timestamp, packet.rssi))
            # Keep only last 100 RSSI values
            if len(device_info['rssi_history']) > 100:
                device_info['rssi_history'] = device_info['rssi_history'][-100:]
    
    async def connect_hfp_device(self, address: str) -> Optional[str]:
        """Connect to an HFP device and monitor the connection"""
        self.logger.info(f"Attempting HFP connection to {address}")
        
        # Connect
        connection = await self.classic_adapter.connect_hfp(address)
        if not connection:
            return None
        
        # Update statistics
        self.statistics['classic']['hfp_connections'] += 1
        
        # Get handler for this device
        if address not in self.hfp_handlers:
            self.hfp_handlers[address] = HFPProtocolHandler()
        
        handler = self.hfp_handlers[address]
        handler.state = handler.HFPState.CONNECTING
        
        return connection.id
    
    async def analyze_hfp_failure(self, address: str) -> Dict[str, Any]:
        """Analyze HFP connection failure for a device"""
        if address not in self.hfp_handlers:
            return {'error': 'No HFP handler for device'}
        
        handler = self.hfp_handlers[address]
        analysis = handler.analyze_failure()
        
        # Add SCO analysis if available
        if self.classic_adapter.has_active_sco():
            sco_analysis = self.sco_analyzer.analyze_codec_performance()
            analysis['sco_analysis'] = sco_analysis
        
        return analysis
    
    def get_unified_status(self) -> Dict[str, Any]:
        """Get status of both BLE and Classic Bluetooth"""
        return {
            'timestamp': datetime.now().isoformat(),
            'ble': {
                'enabled': self.ble_interface is not None,
                'devices': len(self.ble_devices),
                'statistics': self.statistics['ble']
            },
            'classic': {
                'enabled': True,
                'devices': len(self.classic_devices),
                'hfp_handlers': len(self.hfp_handlers),
                'active_sco': self.classic_adapter.has_active_sco(),
                'statistics': self.statistics['classic']
            },
            'monitoring': self.monitoring
        }
    
    def get_device_list(self) -> Dict[str, Any]:
        """Get list of all discovered devices"""
        return {
            'ble_devices': [
                {
                    'address': addr,
                    'name': info['device'].name,
                    'rssi': info['device'].rssi,
                    'last_seen': info['last_seen'].isoformat()
                }
                for addr, info in self.ble_devices.items()
            ],
            'classic_devices': [
                {
                    'address': device.address,
                    'name': device.name,
                    'profiles': device.profiles,
                    'paired': device.paired,
                    'connected': device.connected
                }
                for device in self.classic_devices.values()
            ]
        }
    
    async def test_hfp_connection(self, address: str) -> Dict[str, Any]:
        """Test HFP connection to a device"""
        result = {
            'address': address,
            'timestamp': datetime.now().isoformat(),
            'success': False,
            'steps': []
        }
        
        # Step 1: Connect HFP
        result['steps'].append({'step': 'HFP Connect', 'status': 'starting'})
        connection_id = await self.connect_hfp_device(address)
        
        if not connection_id:
            result['steps'][-1]['status'] = 'failed'
            return result
        
        result['steps'][-1]['status'] = 'success'
        result['steps'][-1]['connection_id'] = connection_id
        
        # Step 2: Establish SCO
        result['steps'].append({'step': 'SCO Setup', 'status': 'starting'})
        sco_connected = await self.classic_adapter.connect_sco(connection_id)
        
        if not sco_connected:
            result['steps'][-1]['status'] = 'failed'
            result['failure_analysis'] = await self.analyze_hfp_failure(address)
        else:
            result['steps'][-1]['status'] = 'success'
            result['success'] = True
            
            # Step 3: Analyze audio quality
            result['steps'].append({'step': 'Audio Analysis', 'status': 'starting'})
            metrics = await self.sco_analyzer.analyze_sco_stream(0, duration=5)
            result['steps'][-1]['status'] = 'success'
            result['audio_metrics'] = {
                'codec': metrics.codec,
                'quality_score': self.sco_analyzer._calculate_quality_score(),
                'packet_loss': metrics.packet_loss_rate,
                'latency': metrics.average_latency,
                'jitter': metrics.jitter
            }
        
        # Disconnect
        await self.classic_adapter.disconnect(connection_id)
        
        return result