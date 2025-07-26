#!/usr/bin/env python3
"""
Realtek RTL8723D Firmware Loader
Native Python implementation to replace rtk_hciattach
"""

import serial
import struct
import asyncio
import logging
from typing import Optional, Tuple, List
from pathlib import Path
from dataclasses import dataclass
from enum import IntEnum

logger = logging.getLogger(__name__)

class H5PacketType(IntEnum):
    """H5 (Three-wire UART) packet types"""
    ACK = 0x00
    HCI_COMMAND = 0x01
    HCI_ACLDATA = 0x02
    HCI_SCODATA = 0x03
    HCI_EVENT = 0x04
    VENDOR = 0x0E
    LINK_CONTROL = 0x0F

@dataclass
class FirmwareHeader:
    """RTL firmware header structure"""
    signature: bytes  # "Realtech"
    version: int
    num_patches: int
    patch_length: int
    
    @classmethod
    def from_bytes(cls, data: bytes):
        # Parse RTL firmware header
        sig = data[0:8]
        ver = struct.unpack('<H', data[8:10])[0]
        num = struct.unpack('<H', data[10:12])[0]
        length = struct.unpack('<I', data[12:16])[0]
        return cls(sig, ver, num, length)

class H5Protocol:
    """Three-wire UART (H5) protocol handler"""
    
    def __init__(self):
        self.seq_num = 0
        self.ack_num = 0
        self.sliding_window = []
        
    def create_packet(self, pkt_type: H5PacketType, payload: bytes) -> bytes:
        """Create H5 packet with header and checksum"""
        # H5 header: 4 bytes
        # Bit 7: Seq number
        # Bit 6-4: ACK number  
        # Bit 3: Data integrity check present
        # Bit 2-0: Packet type
        
        header = bytearray(4)
        header[0] = 0xC0  # SLIP start
        header[1] = (self.seq_num << 3) | (self.ack_num & 0x07)
        header[2] = pkt_type & 0x0F
        header[3] = len(payload) & 0xFF
        
        # Calculate checksum
        checksum = 0
        for b in header[1:]:
            checksum ^= b
        for b in payload:
            checksum ^= b
            
        # Build complete packet
        packet = header + payload + bytes([checksum, 0xC0])  # SLIP end
        
        self.seq_num = (self.seq_num + 1) % 8
        return packet
    
    def parse_packet(self, data: bytes) -> Tuple[H5PacketType, bytes]:
        """Parse H5 packet and extract payload"""
        if len(data) < 6 or data[0] != 0xC0 or data[-1] != 0xC0:
            raise ValueError("Invalid H5 packet")
            
        seq = (data[1] >> 3) & 0x07
        ack = data[1] & 0x07
        pkt_type = data[2] & 0x0F
        length = data[3]
        
        payload = data[4:-2]
        checksum = data[-2]
        
        # Verify checksum
        calc_checksum = 0
        for b in data[1:-2]:
            calc_checksum ^= b
            
        if calc_checksum != checksum:
            raise ValueError("Checksum mismatch")
            
        self.ack_num = seq
        return H5PacketType(pkt_type), payload

class RTL8723DFirmwareLoader:
    """Load firmware to RTL8723D via UART"""
    
    def __init__(self, uart_device: str = "/dev/ttyS5", baud_rate: int = 115200):
        self.uart_device = uart_device
        self.baud_rate = baud_rate
        self.h5 = H5Protocol()
        self.serial: Optional[serial.Serial] = None
        
    async def connect(self) -> bool:
        """Open UART connection"""
        try:
            self.serial = serial.Serial(
                self.uart_device,
                self.baud_rate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=1.0,
                xonxoff=False,
                rtscts=True
            )
            logger.info(f"Connected to {self.uart_device} at {self.baud_rate} baud")
            return True
        except Exception as e:
            logger.error(f"Failed to open UART: {e}")
            return False
    
    async def send_hci_command(self, opcode: int, params: bytes = b'') -> bytes:
        """Send HCI command and wait for response"""
        # HCI command packet format
        cmd = struct.pack('<HB', opcode, len(params)) + params
        
        # Wrap in H5 packet
        packet = self.h5.create_packet(H5PacketType.HCI_COMMAND, cmd)
        
        # Send packet
        self.serial.write(packet)
        self.serial.flush()
        
        # Wait for response
        response = await self.read_packet()
        return response
    
    async def read_packet(self, timeout: float = 1.0) -> bytes:
        """Read H5 packet from UART"""
        self.serial.timeout = timeout
        
        # Read until we get SLIP start
        while True:
            byte = self.serial.read(1)
            if not byte:
                raise TimeoutError("No response from device")
            if byte[0] == 0xC0:
                break
        
        # Read rest of packet
        packet = bytearray([0xC0])
        while True:
            byte = self.serial.read(1)
            if not byte:
                raise TimeoutError("Incomplete packet")
            packet.append(byte[0])
            if byte[0] == 0xC0 and len(packet) > 1:
                break
        
        # Parse packet
        pkt_type, payload = self.h5.parse_packet(bytes(packet))
        return payload
    
    async def read_local_version(self) -> dict:
        """Read local version information"""
        # HCI_Read_Local_Version_Information
        response = await self.send_hci_command(0x1001)
        
        if len(response) < 14:
            raise ValueError("Invalid version response")
        
        version = {
            'hci_version': response[6],
            'hci_revision': struct.unpack('<H', response[7:9])[0],
            'lmp_version': response[9],
            'manufacturer': struct.unpack('<H', response[10:12])[0],
            'lmp_subversion': struct.unpack('<H', response[12:14])[0]
        }
        
        logger.info(f"Device version: {version}")
        return version
    
    async def load_firmware(self, fw_path: str, config_path: str) -> bool:
        """Load firmware and config to device"""
        try:
            # Step 1: HCI Reset
            logger.info("Sending HCI Reset...")
            await self.send_hci_command(0x0C03)  # HCI_Reset
            await asyncio.sleep(0.5)
            
            # Step 2: Read version to check if we need firmware
            version = await self.read_local_version()
            
            if version['lmp_subversion'] == 0x8723:
                logger.info("Firmware already loaded")
                return True
            
            # Step 3: Enter download mode
            logger.info("Entering download mode...")
            download_cmd = bytes([0x01, 0x00, 0xFC, 0x01, 0x01])
            self.serial.write(download_cmd)
            await asyncio.sleep(0.1)
            
            # Step 4: Load firmware patches
            logger.info(f"Loading firmware from {fw_path}...")
            fw_data = Path(fw_path).read_bytes()
            
            # Parse firmware header
            header = FirmwareHeader.from_bytes(fw_data[:16])
            logger.info(f"Firmware: {header.num_patches} patches, {header.patch_length} bytes each")
            
            # Send firmware in chunks
            chunk_size = 252  # Max HCI packet payload
            offset = 16  # Skip header
            
            while offset < len(fw_data):
                chunk = fw_data[offset:offset + chunk_size]
                if not chunk:
                    break
                
                # Vendor specific command to download firmware
                download_packet = struct.pack('<BH', 0x20, len(chunk)) + chunk
                await self.send_hci_command(0xFC20, download_packet)
                
                offset += chunk_size
                progress = (offset / len(fw_data)) * 100
                if progress % 10 < (chunk_size / len(fw_data)) * 100:
                    logger.info(f"Progress: {progress:.0f}%")
            
            # Step 5: Load config
            logger.info(f"Loading config from {config_path}...")
            config_data = Path(config_path).read_bytes()
            
            # Send config
            await self.send_hci_command(0xFC61, config_data)
            
            # Step 6: Launch firmware
            logger.info("Launching firmware...")
            launch_cmd = bytes([0x01, 0x00, 0xFC, 0x01, 0x00])
            self.serial.write(launch_cmd)
            
            # Wait for device to restart
            await asyncio.sleep(2.0)
            
            # Step 7: Final HCI Reset
            await self.send_hci_command(0x0C03)
            await asyncio.sleep(0.5)
            
            # Verify firmware loaded
            new_version = await self.read_local_version()
            if new_version['lmp_subversion'] != version['lmp_subversion']:
                logger.info("Firmware loaded successfully!")
                return True
            else:
                logger.error("Firmware load failed - version unchanged")
                return False
                
        except Exception as e:
            logger.error(f"Firmware load error: {e}")
            return False
        
    async def change_baud_rate(self, new_baud: int) -> bool:
        """Change UART baud rate"""
        logger.info(f"Changing baud rate to {new_baud}...")
        
        # Vendor command to change baud rate
        # Format: 0xFC17 [4 bytes little-endian baud rate]
        baud_cmd = struct.pack('<I', new_baud)
        await self.send_hci_command(0xFC17, baud_cmd)
        
        # Give device time to switch
        await asyncio.sleep(0.1)
        
        # Reconfigure our UART
        self.serial.baudrate = new_baud
        self.baud_rate = new_baud
        
        # Test new baud rate
        try:
            await self.send_hci_command(0x1001)  # Read version
            logger.info(f"Baud rate changed to {new_baud}")
            return True
        except:
            logger.error("Failed to communicate at new baud rate")
            return False
    
    async def setup_device(self) -> bool:
        """Complete device initialization"""
        if not await self.connect():
            return False
        
        try:
            # Load firmware
            fw_loaded = await self.load_firmware(
                "/lib/firmware/rtlbt/rtl8723d_fw",
                "/lib/firmware/rtlbt/rtl8723d_config"
            )
            
            if not fw_loaded:
                return False
            
            # Switch to high speed
            if self.baud_rate != 1500000:
                await self.change_baud_rate(1500000)
            
            # Configure device
            logger.info("Configuring device...")
            
            # Set BD address if needed
            # await self.send_hci_command(0xFC06, bd_addr)
            
            # Enable SCO over HCI
            await self.send_hci_command(0xFC1B, bytes([0x00, 0x00]))
            
            # Set event mask
            event_mask = bytes([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
            await self.send_hci_command(0x0C01, event_mask)
            
            logger.info("RTL8723D initialization complete!")
            return True
            
        except Exception as e:
            logger.error(f"Setup failed: {e}")
            return False
        finally:
            if self.serial:
                self.serial.close()

async def main():
    """Test firmware loader"""
    logging.basicConfig(level=logging.INFO)
    
    loader = RTL8723DFirmwareLoader("/dev/ttyS5", 115200)
    success = await loader.setup_device()
    
    if success:
        print("✅ RTL8723D initialized successfully!")
    else:
        print("❌ RTL8723D initialization failed")

if __name__ == "__main__":
    asyncio.run(main())