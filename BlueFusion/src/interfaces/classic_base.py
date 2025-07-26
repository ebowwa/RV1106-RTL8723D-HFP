"""
Base classes and data models for Classic Bluetooth interfaces
Extends BlueFusion to support Classic Bluetooth alongside BLE
"""

from abc import ABC, abstractmethod
from typing import AsyncIterator, Dict, Any, Optional, List, Tuple
from datetime import datetime
from pydantic import BaseModel
from enum import Enum

class ClassicDeviceType(str, Enum):
    """Classic Bluetooth device types"""
    CLASSIC_ADAPTER = "classic_adapter"
    DUAL_MODE = "dual_mode"

class ClassicProfile(str, Enum):
    """Classic Bluetooth profiles"""
    HFP_AG = "hfp_ag"
    HFP_HF = "hfp_hf"
    HSP_AG = "hsp_ag"
    HSP_HS = "hsp_hs"
    A2DP_SOURCE = "a2dp_source"
    A2DP_SINK = "a2dp_sink"
    AVRCP = "avrcp"
    PBAP = "pbap"
    MAP = "map"

class ClassicPacketType(str, Enum):
    """Classic Bluetooth packet types"""
    ACL = "acl"
    SCO = "sco"
    ESCO = "esco"
    L2CAP = "l2cap"
    RFCOMM = "rfcomm"
    SDP = "sdp"
    AT_COMMAND = "at_command"

class ClassicPacket(BaseModel):
    """Classic Bluetooth packet data model"""
    timestamp: datetime
    source: ClassicDeviceType
    address: str
    packet_type: ClassicPacketType
    connection_handle: Optional[int] = None
    data: bytes
    direction: str = "unknown"  # "TX", "RX", or "unknown"
    rssi: Optional[int] = None
    link_quality: Optional[int] = None
    metadata: Dict[str, Any] = {}
    
    class Config:
        arbitrary_types_allowed = True

class ClassicDevice(BaseModel):
    """Classic Bluetooth device model"""
    address: str
    name: Optional[str] = None
    device_class: int = 0
    manufacturer: Optional[str] = None
    rssi: Optional[int] = None
    link_quality: Optional[int] = None
    supported_profiles: List[ClassicProfile] = []
    paired: bool = False
    connected: bool = False
    trusted: bool = False
    services: Dict[str, Any] = {}
    last_seen: datetime = None
    
    class Config:
        arbitrary_types_allowed = True

class AudioCodec(str, Enum):
    """Audio codecs for Classic Bluetooth"""
    CVSD = "cvsd"
    MSBC = "msbc"
    LC3_SWB = "lc3_swb"
    SBC = "sbc"
    AAC = "aac"
    APTX = "aptx"
    APTX_HD = "aptx_hd"
    LDAC = "ldac"

class AudioConnection(BaseModel):
    """Audio connection information"""
    profile: ClassicProfile
    codec: AudioCodec
    sample_rate: int
    bitrate: int
    channel_mode: str  # "mono", "stereo", "joint_stereo"
    active: bool = False
    
class HFPConnection(BaseModel):
    """HFP connection state"""
    device: ClassicDevice
    role: str  # "AG" or "HF"
    state: str  # Connection state
    service_level_connected: bool = False
    audio_connected: bool = False
    codec: AudioCodec = AudioCodec.CVSD
    features: Dict[str, bool] = {}
    indicators: Dict[str, int] = {}
    call_active: bool = False
    
    class Config:
        arbitrary_types_allowed = True

class ClassicBluetoothInterface(ABC):
    """Abstract interface for Classic Bluetooth operations"""
    
    @abstractmethod
    async def scan_classic_devices(self, duration: int = 10) -> List[ClassicDevice]:
        """Scan for Classic Bluetooth devices"""
        pass
    
    @abstractmethod
    async def connect_profile(self, address: str, profile: ClassicProfile) -> bool:
        """Connect to a specific profile on a device"""
        pass
    
    @abstractmethod
    async def disconnect_profile(self, address: str, profile: ClassicProfile) -> bool:
        """Disconnect a specific profile"""
        pass
    
    @abstractmethod
    async def pair_device(self, address: str, pin: Optional[str] = None) -> bool:
        """Pair with a Classic Bluetooth device"""
        pass
    
    @abstractmethod
    async def get_device_info(self, address: str) -> Optional[ClassicDevice]:
        """Get detailed information about a device"""
        pass
    
    @abstractmethod
    async def monitor_packets(self) -> AsyncIterator[ClassicPacket]:
        """Monitor Classic Bluetooth packets"""
        pass

class HFPInterface(ABC):
    """Abstract interface for HFP operations"""
    
    @abstractmethod
    async def connect_hfp(self, address: str, role: str = "HF") -> Optional[HFPConnection]:
        """Establish HFP connection"""
        pass
    
    @abstractmethod
    async def send_at_command(self, connection_id: str, command: str) -> str:
        """Send AT command and get response"""
        pass
    
    @abstractmethod
    async def answer_call(self, connection_id: str) -> bool:
        """Answer incoming call"""
        pass
    
    @abstractmethod
    async def end_call(self, connection_id: str) -> bool:
        """End active call"""
        pass
    
    @abstractmethod
    async def dial_number(self, connection_id: str, number: str) -> bool:
        """Dial a phone number"""
        pass
    
    @abstractmethod
    async def set_volume(self, connection_id: str, volume: int) -> bool:
        """Set speaker/microphone volume (0-15)"""
        pass
    
    @abstractmethod
    async def get_connection_status(self, connection_id: str) -> Optional[HFPConnection]:
        """Get current HFP connection status"""
        pass

class A2DPInterface(ABC):
    """Abstract interface for A2DP operations"""
    
    @abstractmethod
    async def connect_a2dp(self, address: str, role: str = "sink") -> bool:
        """Connect A2DP profile"""
        pass
    
    @abstractmethod
    async def get_codec_capabilities(self, address: str) -> List[AudioCodec]:
        """Get supported codecs"""
        pass
    
    @abstractmethod
    async def select_codec(self, address: str, codec: AudioCodec) -> bool:
        """Select audio codec"""
        pass
    
    @abstractmethod
    async def get_audio_stats(self, address: str) -> Dict[str, Any]:
        """Get audio streaming statistics"""
        pass