"""
Classic Bluetooth support for BlueFusion
Adds HFP, HSP, A2DP and SCO audio analysis capabilities
"""

from .classic_adapter import ClassicBluetoothAdapter
from .hfp_handler import HFPProtocolHandler
from .sco_audio import SCOAudioAnalyzer

__all__ = ['ClassicBluetoothAdapter', 'HFPProtocolHandler', 'SCOAudioAnalyzer']