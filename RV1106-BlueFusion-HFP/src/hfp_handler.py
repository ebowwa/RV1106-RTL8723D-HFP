"""
HFP Protocol Handler for BlueFusion
Handles AT commands and HFP state machine
"""

import re
import time
import logging
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, field
from enum import Enum

class HFPState(Enum):
    """HFP connection states"""
    DISCONNECTED = "DISCONNECTED"
    CONNECTING = "CONNECTING"
    SLC_CONNECTING = "SLC_CONNECTING"
    CONNECTED = "CONNECTED"
    AUDIO_CONNECTING = "AUDIO_CONNECTING"
    AUDIO_CONNECTED = "AUDIO_CONNECTED"
    DISCONNECTING = "DISCONNECTING"

class HFPRole(Enum):
    """HFP roles"""
    AG = "AudioGateway"
    HF = "HandsFree"

@dataclass
class ATCommand:
    """Represents an AT command and response"""
    timestamp: float
    command: str
    response: str
    direction: str  # "TX" or "RX"
    state: HFPState
    
@dataclass
class HFPFeatures:
    """HFP feature flags"""
    # HF features
    ec_nr: bool = False           # Echo Cancel/Noise Reduction
    three_way_calling: bool = False
    cli_presentation: bool = False
    voice_recognition: bool = False
    remote_volume_control: bool = False
    enhanced_call_status: bool = False
    enhanced_call_control: bool = False
    codec_negotiation: bool = False
    hf_indicators: bool = False
    esco_s4: bool = False
    
    # AG features
    ag_three_way_calling: bool = False
    ag_ec_nr: bool = False
    ag_voice_recognition: bool = False
    ag_inband_ringtone: bool = False
    ag_voice_tag: bool = False
    ag_reject_call: bool = False
    ag_enhanced_call_status: bool = False
    ag_enhanced_call_control: bool = False
    ag_extended_error: bool = False
    ag_codec_negotiation: bool = False

class HFPProtocolHandler:
    """HFP AT command handling and state machine"""
    
    # HF feature bits
    HF_FEAT_ECNR = 0x01
    HF_FEAT_3WAY = 0x02
    HF_FEAT_CLI = 0x04
    HF_FEAT_VR = 0x08
    HF_FEAT_RVOL = 0x10
    HF_FEAT_ECS = 0x20
    HF_FEAT_ECC = 0x40
    HF_FEAT_CODEC = 0x80
    HF_FEAT_HF_IND = 0x100
    HF_FEAT_ESCO_S4 = 0x200
    
    # AG feature bits
    AG_FEAT_3WAY = 0x01
    AG_FEAT_ECNR = 0x02
    AG_FEAT_VR = 0x04
    AG_FEAT_RING = 0x08
    AG_FEAT_VTAG = 0x10
    AG_FEAT_REJECT = 0x20
    AG_FEAT_ECS = 0x40
    AG_FEAT_ECC = 0x80
    AG_FEAT_EERR = 0x100
    AG_FEAT_CODEC = 0x200
    
    def __init__(self, role: HFPRole = HFPRole.HF):
        self.logger = logging.getLogger(__name__)
        self.role = role
        self.state = HFPState.DISCONNECTED
        self.features = HFPFeatures()
        self.at_command_flow: List[ATCommand] = []
        self.supported_codecs = ["CVSD"]  # Default codec
        self.selected_codec = "CVSD"
        self.indicators = {}
        self.call_state = {
            'active': False,
            'incoming': False,
            'outgoing': False,
            'number': None
        }
        
    def process_at_command(self, command: str, response: str = "", direction: str = "TX"):
        """Process an AT command and update state"""
        at_cmd = ATCommand(
            timestamp=time.time(),
            command=command.strip(),
            response=response.strip(),
            direction=direction,
            state=self.state
        )
        self.at_command_flow.append(at_cmd)
        
        # Parse command
        if direction == "TX":
            self._handle_outgoing_command(command)
        else:
            self._handle_incoming_command(command, response)
    
    def _handle_outgoing_command(self, command: str):
        """Handle commands sent by HF"""
        if command.startswith("AT+BRSF="):
            # Features exchange
            features = int(command.split("=")[1])
            self._parse_hf_features(features)
            self.state = HFPState.SLC_CONNECTING
            
        elif command == "AT+BAC":
            # Available codecs
            self.state = HFPState.SLC_CONNECTING
            
        elif command == "AT+CIND=?":
            # Query indicators
            pass
            
        elif command == "AT+CIND?":
            # Read indicator status
            pass
            
        elif command == "AT+CMER":
            # Enable indicator reporting
            self.state = HFPState.CONNECTED
            
        elif command == "AT+BCC":
            # Codec connection request
            self.state = HFPState.AUDIO_CONNECTING
    
    def _handle_incoming_command(self, command: str, response: str):
        """Handle commands/responses from AG"""
        if command.startswith("+BRSF:"):
            # AG features
            features = int(command.split(":")[1])
            self._parse_ag_features(features)
            
        elif command.startswith("+BAC:"):
            # AG codec list
            codecs = command.split(":")[1].split(",")
            self.supported_codecs = []
            for codec in codecs:
                if codec.strip() == "1":
                    self.supported_codecs.append("CVSD")
                elif codec.strip() == "2":
                    self.supported_codecs.append("mSBC")
                    
        elif command.startswith("+BCS:"):
            # Codec selection
            codec_id = int(command.split(":")[1])
            self.selected_codec = "mSBC" if codec_id == 2 else "CVSD"
            self.state = HFPState.AUDIO_CONNECTED
            
        elif command.startswith("+CIND:"):
            # Indicator values
            self._parse_indicators(command)
            
        elif command.startswith("+CIEV:"):
            # Indicator event
            self._handle_indicator_event(command)
    
    def _parse_hf_features(self, features: int):
        """Parse HF feature flags"""
        self.features.ec_nr = bool(features & self.HF_FEAT_ECNR)
        self.features.three_way_calling = bool(features & self.HF_FEAT_3WAY)
        self.features.cli_presentation = bool(features & self.HF_FEAT_CLI)
        self.features.voice_recognition = bool(features & self.HF_FEAT_VR)
        self.features.remote_volume_control = bool(features & self.HF_FEAT_RVOL)
        self.features.enhanced_call_status = bool(features & self.HF_FEAT_ECS)
        self.features.enhanced_call_control = bool(features & self.HF_FEAT_ECC)
        self.features.codec_negotiation = bool(features & self.HF_FEAT_CODEC)
        self.features.hf_indicators = bool(features & self.HF_FEAT_HF_IND)
        self.features.esco_s4 = bool(features & self.HF_FEAT_ESCO_S4)
    
    def _parse_ag_features(self, features: int):
        """Parse AG feature flags"""
        self.features.ag_three_way_calling = bool(features & self.AG_FEAT_3WAY)
        self.features.ag_ec_nr = bool(features & self.AG_FEAT_ECNR)
        self.features.ag_voice_recognition = bool(features & self.AG_FEAT_VR)
        self.features.ag_inband_ringtone = bool(features & self.AG_FEAT_RING)
        self.features.ag_voice_tag = bool(features & self.AG_FEAT_VTAG)
        self.features.ag_reject_call = bool(features & self.AG_FEAT_REJECT)
        self.features.ag_enhanced_call_status = bool(features & self.AG_FEAT_ECS)
        self.features.ag_enhanced_call_control = bool(features & self.AG_FEAT_ECC)
        self.features.ag_extended_error = bool(features & self.AG_FEAT_EERR)
        self.features.ag_codec_negotiation = bool(features & self.AG_FEAT_CODEC)
    
    def _parse_indicators(self, cind_response: str):
        """Parse CIND response"""
        # Example: +CIND: ("call",(0,1)),("callsetup",(0-3)),("service",(0,1))
        pattern = r'"(\w+)",\(([0-9,-]+)\)'
        matches = re.findall(pattern, cind_response)
        
        for name, range_str in matches:
            self.indicators[name] = {
                'range': range_str,
                'value': 0
            }
    
    def _handle_indicator_event(self, ciev_command: str):
        """Handle indicator event"""
        # Example: +CIEV: 2,1 (indicator 2, value 1)
        parts = ciev_command.split(":")
        if len(parts) > 1:
            ind_val = parts[1].split(",")
            if len(ind_val) == 2:
                indicator_idx = int(ind_val[0])
                value = int(ind_val[1])
                
                # Map to indicator name
                ind_names = list(self.indicators.keys())
                if indicator_idx <= len(ind_names):
                    ind_name = ind_names[indicator_idx - 1]
                    self.indicators[ind_name]['value'] = value
                    
                    # Update call state
                    if ind_name == "call":
                        self.call_state['active'] = value == 1
                    elif ind_name == "callsetup":
                        self.call_state['incoming'] = value == 1
                        self.call_state['outgoing'] = value == 2
    
    def analyze_failure(self) -> Dict[str, any]:
        """Analyze HFP connection failure patterns"""
        analysis = {
            'last_state': self.state.value,
            'total_commands': len(self.at_command_flow),
            'features': {
                'codec_negotiation': self.features.codec_negotiation and self.features.ag_codec_negotiation,
                'selected_codec': self.selected_codec,
                'supported_codecs': self.supported_codecs
            },
            'likely_issues': []
        }
        
        # Check for common failure patterns
        if self.state == HFPState.SLC_CONNECTING:
            analysis['likely_issues'].append("Service Level Connection failed")
            
            # Check if codec negotiation failed
            if self.features.codec_negotiation and not any(
                cmd.command.startswith("+BCS") for cmd in self.at_command_flow
            ):
                analysis['likely_issues'].append("Codec negotiation incomplete")
        
        elif self.state == HFPState.AUDIO_CONNECTING:
            analysis['likely_issues'].append("SCO audio connection failed")
            
            # Check codec compatibility
            if "mSBC" in self.supported_codecs and self.selected_codec == "CVSD":
                analysis['likely_issues'].append("mSBC available but not selected")
        
        # Check for timing issues
        if len(self.at_command_flow) > 1:
            cmd_delays = []
            for i in range(1, len(self.at_command_flow)):
                delay = self.at_command_flow[i].timestamp - self.at_command_flow[i-1].timestamp
                cmd_delays.append(delay)
            
            avg_delay = sum(cmd_delays) / len(cmd_delays)
            if avg_delay > 1.0:
                analysis['likely_issues'].append(f"Slow command response (avg: {avg_delay:.2f}s)")
        
        # Get command flow summary
        analysis['command_flow'] = [
            {
                'time': cmd.timestamp - self.at_command_flow[0].timestamp if self.at_command_flow else 0,
                'command': cmd.command,
                'direction': cmd.direction,
                'state': cmd.state.value
            }
            for cmd in self.at_command_flow[-10:]  # Last 10 commands
        ]
        
        return analysis
    
    def get_state_info(self) -> Dict[str, any]:
        """Get current HFP state information"""
        return {
            'state': self.state.value,
            'role': self.role.value,
            'features': {
                'hf': {
                    'codec_negotiation': self.features.codec_negotiation,
                    'wideband': 'mSBC' in self.supported_codecs,
                    'volume_control': self.features.remote_volume_control
                },
                'ag': {
                    'codec_negotiation': self.features.ag_codec_negotiation,
                    'inband_ringtone': self.features.ag_inband_ringtone
                }
            },
            'audio': {
                'codec': self.selected_codec,
                'supported_codecs': self.supported_codecs
            },
            'call_state': self.call_state,
            'indicators': self.indicators
        }
    
    def reset(self):
        """Reset handler state"""
        self.state = HFPState.DISCONNECTED
        self.at_command_flow.clear()
        self.supported_codecs = ["CVSD"]
        self.selected_codec = "CVSD"
        self.indicators.clear()
        self.call_state = {
            'active': False,
            'incoming': False,
            'outgoing': False,
            'number': None
        }