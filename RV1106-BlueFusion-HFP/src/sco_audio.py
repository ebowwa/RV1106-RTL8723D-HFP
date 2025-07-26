"""
SCO Audio Analyzer for BlueFusion
Analyzes SCO audio connections and codec performance
"""

import asyncio
import time
import struct
import logging
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass
import numpy as np

@dataclass
class SCOPacket:
    """Represents an SCO packet"""
    timestamp: float
    connection_handle: int
    packet_status: int
    data: bytes
    length: int
    
@dataclass
class AudioMetrics:
    """Audio quality metrics"""
    packet_loss_rate: float
    average_latency: float
    jitter: float
    codec: str
    bitrate: int
    sample_rate: int
    
class SCOAudioAnalyzer:
    """Analyze SCO audio connections for quality and issues"""
    
    # SCO packet types
    SCO_PACKET_TYPE_HV1 = 0x0020
    SCO_PACKET_TYPE_HV2 = 0x0040
    SCO_PACKET_TYPE_HV3 = 0x0080
    SCO_PACKET_TYPE_EV3 = 0x0008
    SCO_PACKET_TYPE_EV4 = 0x0010
    SCO_PACKET_TYPE_EV5 = 0x0020
    SCO_PACKET_TYPE_2EV3 = 0x0040
    SCO_PACKET_TYPE_3EV3 = 0x0080
    SCO_PACKET_TYPE_2EV5 = 0x0100
    SCO_PACKET_TYPE_3EV5 = 0x0200
    
    # Codec parameters
    CODEC_PARAMS = {
        'CVSD': {
            'sample_rate': 8000,
            'bitrate': 64000,
            'frame_size': 60,
            'packet_types': [SCO_PACKET_TYPE_HV1, SCO_PACKET_TYPE_HV3]
        },
        'mSBC': {
            'sample_rate': 16000,
            'bitrate': 64000,
            'frame_size': 60,
            'packet_types': [SCO_PACKET_TYPE_EV3, SCO_PACKET_TYPE_2EV3]
        },
        'LC3-SWB': {
            'sample_rate': 32000,
            'bitrate': 64000,
            'frame_size': 60,
            'packet_types': [SCO_PACKET_TYPE_EV5, SCO_PACKET_TYPE_2EV5]
        }
    }
    
    def __init__(self):
        self.logger = logging.getLogger(__name__)
        self.packets: List[SCOPacket] = []
        self.codec = "CVSD"
        self.metrics = None
        self.analyzing = False
        
    async def analyze_sco_stream(self, socket_fd: int, codec: str = "CVSD", duration: int = 10):
        """Analyze SCO audio stream"""
        self.codec = codec
        self.packets.clear()
        self.analyzing = True
        
        self.logger.info(f"Starting SCO analysis for {codec} codec, duration: {duration}s")
        
        start_time = time.time()
        packet_count = 0
        
        try:
            while self.analyzing and (time.time() - start_time) < duration:
                # Read SCO packet (simplified - real implementation would use HCI)
                try:
                    # In real implementation, read from SCO socket
                    # For now, simulate packet reception
                    await asyncio.sleep(0.00625)  # 6.25ms for HV3
                    
                    # Simulate packet
                    packet = SCOPacket(
                        timestamp=time.time(),
                        connection_handle=0x0001,
                        packet_status=0x00,  # Good packet
                        data=b'\x00' * 60,  # Dummy data
                        length=60
                    )
                    
                    self.packets.append(packet)
                    packet_count += 1
                    
                except Exception as e:
                    self.logger.error(f"Error reading SCO packet: {e}")
                    
        except Exception as e:
            self.logger.error(f"SCO analysis error: {e}")
            
        finally:
            self.analyzing = False
            
        # Calculate metrics
        self.metrics = self._calculate_metrics()
        
        self.logger.info(f"SCO analysis complete. Analyzed {packet_count} packets")
        
        return self.metrics
    
    def _calculate_metrics(self) -> AudioMetrics:
        """Calculate audio quality metrics"""
        if len(self.packets) < 2:
            return AudioMetrics(
                packet_loss_rate=0.0,
                average_latency=0.0,
                jitter=0.0,
                codec=self.codec,
                bitrate=self.CODEC_PARAMS[self.codec]['bitrate'],
                sample_rate=self.CODEC_PARAMS[self.codec]['sample_rate']
            )
        
        # Calculate packet loss
        good_packets = sum(1 for p in self.packets if p.packet_status == 0x00)
        packet_loss_rate = 1.0 - (good_packets / len(self.packets))
        
        # Calculate inter-packet delays
        delays = []
        for i in range(1, len(self.packets)):
            delay = self.packets[i].timestamp - self.packets[i-1].timestamp
            delays.append(delay * 1000)  # Convert to ms
        
        # Calculate average latency and jitter
        average_latency = np.mean(delays) if delays else 0.0
        jitter = np.std(delays) if delays else 0.0
        
        return AudioMetrics(
            packet_loss_rate=packet_loss_rate,
            average_latency=average_latency,
            jitter=jitter,
            codec=self.codec,
            bitrate=self.CODEC_PARAMS[self.codec]['bitrate'],
            sample_rate=self.CODEC_PARAMS[self.codec]['sample_rate']
        )
    
    def analyze_codec_performance(self) -> Dict[str, any]:
        """Analyze codec-specific performance issues"""
        if not self.metrics:
            return {'error': 'No metrics available'}
        
        analysis = {
            'codec': self.codec,
            'quality_score': self._calculate_quality_score(),
            'issues': [],
            'recommendations': []
        }
        
        # Check packet loss
        if self.metrics.packet_loss_rate > 0.05:  # 5% threshold
            analysis['issues'].append(f"High packet loss: {self.metrics.packet_loss_rate:.1%}")
            analysis['recommendations'].append("Check RF interference or increase transmit power")
        
        # Check latency
        expected_latency = 7.5 if self.codec == "CVSD" else 10.0  # ms
        if self.metrics.average_latency > expected_latency * 1.5:
            analysis['issues'].append(f"High latency: {self.metrics.average_latency:.1f}ms")
            analysis['recommendations'].append("Check CPU load or buffer settings")
        
        # Check jitter
        if self.metrics.jitter > 2.0:  # 2ms threshold
            analysis['issues'].append(f"High jitter: {self.metrics.jitter:.1f}ms")
            analysis['recommendations'].append("Check for scheduling issues or USB interference")
        
        # Codec-specific checks
        if self.codec == "mSBC":
            if self.metrics.packet_loss_rate > 0.02:  # mSBC more sensitive
                analysis['recommendations'].append("Consider falling back to CVSD for better reliability")
        
        return analysis
    
    def _calculate_quality_score(self) -> float:
        """Calculate overall audio quality score (0-100)"""
        if not self.metrics:
            return 0.0
        
        # Weight factors
        packet_loss_weight = 0.5
        latency_weight = 0.3
        jitter_weight = 0.2
        
        # Calculate individual scores
        packet_loss_score = max(0, 100 - (self.metrics.packet_loss_rate * 1000))
        
        expected_latency = 7.5 if self.codec == "CVSD" else 10.0
        latency_score = max(0, 100 - ((self.metrics.average_latency - expected_latency) * 10))
        
        jitter_score = max(0, 100 - (self.metrics.jitter * 25))
        
        # Combined score
        quality_score = (
            packet_loss_score * packet_loss_weight +
            latency_score * latency_weight +
            jitter_score * jitter_weight
        )
        
        return min(100, max(0, quality_score))
    
    def get_packet_timing_analysis(self) -> Dict[str, any]:
        """Analyze packet timing patterns"""
        if len(self.packets) < 10:
            return {'error': 'Insufficient packets for timing analysis'}
        
        # Calculate inter-packet intervals
        intervals = []
        for i in range(1, len(self.packets)):
            interval = (self.packets[i].timestamp - self.packets[i-1].timestamp) * 1000
            intervals.append(interval)
        
        # Expected intervals based on codec
        expected_interval = {
            'CVSD': 6.25,    # HV3
            'mSBC': 7.5,     # EV3
            'LC3-SWB': 10.0  # EV5
        }.get(self.codec, 7.5)
        
        # Find anomalies
        anomalies = []
        for i, interval in enumerate(intervals):
            if abs(interval - expected_interval) > expected_interval * 0.2:  # 20% deviation
                anomalies.append({
                    'packet_index': i + 1,
                    'interval': interval,
                    'deviation': interval - expected_interval
                })
        
        return {
            'expected_interval': expected_interval,
            'average_interval': np.mean(intervals),
            'min_interval': np.min(intervals),
            'max_interval': np.max(intervals),
            'std_deviation': np.std(intervals),
            'anomaly_count': len(anomalies),
            'anomaly_rate': len(anomalies) / len(intervals),
            'timing_stability': 'stable' if len(anomalies) / len(intervals) < 0.05 else 'unstable'
        }
    
    def suggest_sco_parameters(self, rf_conditions: str = "normal") -> Dict[str, any]:
        """Suggest optimal SCO parameters based on conditions"""
        suggestions = {
            'codec': self.codec,
            'packet_type': None,
            'max_latency': None,
            'retransmission': None,
            'reason': []
        }
        
        if rf_conditions == "poor" or (self.metrics and self.metrics.packet_loss_rate > 0.1):
            # Poor RF conditions - prioritize reliability
            suggestions['codec'] = "CVSD"
            suggestions['packet_type'] = "HV3"
            suggestions['max_latency'] = 20
            suggestions['retransmission'] = True
            suggestions['reason'].append("Poor RF conditions detected - using most reliable settings")
            
        elif rf_conditions == "excellent" and self.codec == "mSBC":
            # Excellent conditions - can use higher quality
            suggestions['codec'] = "mSBC"
            suggestions['packet_type'] = "2-EV3"
            suggestions['max_latency'] = 10
            suggestions['retransmission'] = False
            suggestions['reason'].append("Excellent conditions - optimizing for quality")
            
        else:
            # Normal conditions - balanced approach
            suggestions['codec'] = self.codec
            suggestions['packet_type'] = "EV3" if self.codec == "mSBC" else "HV3"
            suggestions['max_latency'] = 15
            suggestions['retransmission'] = True
            suggestions['reason'].append("Standard settings for typical conditions")
        
        return suggestions