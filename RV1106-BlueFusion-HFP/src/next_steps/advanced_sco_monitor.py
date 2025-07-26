#!/usr/bin/env python3
"""
Advanced SCO Audio Monitor with ML-based Quality Prediction
Real-time analysis and predictive failure detection
"""

import numpy as np
import asyncio
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Tuple
from collections import deque
from datetime import datetime, timedelta
import struct
import logging
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler
import joblib
import pandas as pd

logger = logging.getLogger(__name__)

@dataclass
class SCOPacketInfo:
    """Enhanced SCO packet information"""
    timestamp: datetime
    sequence_number: int
    payload_size: int
    rssi: int
    link_quality: int
    error_rate: float
    codec_type: str  # CVSD or mSBC
    raw_data: bytes = field(repr=False)
    
    @property
    def latency_marker(self) -> int:
        """Extract latency marker from payload if present"""
        if len(self.raw_data) >= 4:
            return struct.unpack('<I', self.raw_data[:4])[0]
        return 0

@dataclass 
class AudioQualityMetrics:
    """Comprehensive audio quality metrics"""
    # Basic metrics
    packet_loss_rate: float
    average_latency: float
    latency_p95: float
    latency_p99: float
    jitter: float
    jitter_variance: float
    
    # Advanced metrics
    mos_score: float  # Mean Opinion Score (1-5)
    pesq_score: float  # Perceptual Evaluation of Speech Quality
    signal_to_noise: float
    echo_likelihood: float
    
    # Predictive metrics
    failure_probability: float
    quality_trend: str  # "improving", "stable", "degrading"
    estimated_time_to_failure: Optional[float]  # seconds
    
    # Codec-specific
    codec_switches: int
    codec_efficiency: float

class AdvancedSCOMonitor:
    """Advanced SCO monitoring with ML-based predictions"""
    
    def __init__(self, model_path: Optional[str] = None):
        # Buffers
        self.packet_buffer = deque(maxlen=10000)
        self.latency_buffer = deque(maxlen=1000)
        self.quality_history = deque(maxlen=600)  # 10 minutes at 1Hz
        
        # Metrics
        self.total_packets = 0
        self.lost_packets = 0
        self.codec_switches = 0
        self.last_codec = "CVSD"
        
        # ML model
        self.scaler = StandardScaler()
        self.anomaly_detector = IsolationForest(contamination=0.1)
        self.model_trained = False
        
        if model_path:
            self.load_model(model_path)
        
        # Audio analysis
        self.fft_buffer = np.zeros(1024)
        self.fft_index = 0
        
    def process_sco_packet(self, packet: SCOPacketInfo) -> AudioQualityMetrics:
        """Process SCO packet and return quality metrics"""
        self.packet_buffer.append(packet)
        self.total_packets += 1
        
        # Detect codec switch
        if packet.codec_type != self.last_codec:
            self.codec_switches += 1
            self.last_codec = packet.codec_type
            logger.info(f"Codec switched to {packet.codec_type}")
        
        # Calculate instantaneous metrics
        metrics = self._calculate_metrics(packet)
        
        # Update ML model
        if self.model_trained:
            metrics.failure_probability = self._predict_failure()
            metrics.estimated_time_to_failure = self._estimate_time_to_failure()
        
        # Store history
        self.quality_history.append((datetime.now(), metrics))
        
        return metrics
    
    def _calculate_metrics(self, current_packet: SCOPacketInfo) -> AudioQualityMetrics:
        """Calculate comprehensive quality metrics"""
        if len(self.packet_buffer) < 2:
            return self._default_metrics()
        
        # Packet loss calculation
        expected_packets = current_packet.sequence_number - self.packet_buffer[0].sequence_number
        actual_packets = len(self.packet_buffer)
        packet_loss_rate = max(0, 1 - (actual_packets / expected_packets)) if expected_packets > 0 else 0
        
        # Latency analysis
        latencies = []
        for i in range(1, len(self.packet_buffer)):
            time_diff = (self.packet_buffer[i].timestamp - self.packet_buffer[i-1].timestamp).total_seconds() * 1000
            expected_time = self._get_expected_packet_interval(self.packet_buffer[i].codec_type)
            latency = abs(time_diff - expected_time)
            latencies.append(latency)
            self.latency_buffer.append(latency)
        
        if latencies:
            avg_latency = np.mean(latencies)
            latency_p95 = np.percentile(latencies, 95)
            latency_p99 = np.percentile(latencies, 99)
            jitter = np.std(latencies)
            jitter_variance = np.var(latencies)
        else:
            avg_latency = latency_p95 = latency_p99 = jitter = jitter_variance = 0
        
        # Calculate MOS score (simplified E-model)
        mos_score = self._calculate_mos(packet_loss_rate, avg_latency, jitter)
        
        # Audio quality analysis
        if current_packet.raw_data:
            pesq_score = self._estimate_pesq(current_packet.raw_data)
            snr = self._calculate_snr(current_packet.raw_data)
            echo_likelihood = self._detect_echo_likelihood(current_packet.raw_data)
        else:
            pesq_score = 3.0
            snr = 20.0
            echo_likelihood = 0.0
        
        # Codec efficiency
        codec_efficiency = self._calculate_codec_efficiency(
            current_packet.codec_type,
            packet_loss_rate,
            current_packet.link_quality
        )
        
        # Quality trend
        quality_trend = self._analyze_quality_trend()
        
        return AudioQualityMetrics(
            packet_loss_rate=packet_loss_rate,
            average_latency=avg_latency,
            latency_p95=latency_p95,
            latency_p99=latency_p99,
            jitter=jitter,
            jitter_variance=jitter_variance,
            mos_score=mos_score,
            pesq_score=pesq_score,
            signal_to_noise=snr,
            echo_likelihood=echo_likelihood,
            failure_probability=0.0,  # Will be updated by ML
            quality_trend=quality_trend,
            estimated_time_to_failure=None,
            codec_switches=self.codec_switches,
            codec_efficiency=codec_efficiency
        )
    
    def _get_expected_packet_interval(self, codec: str) -> float:
        """Get expected packet interval in ms"""
        if codec == "mSBC":
            return 7.5  # mSBC uses 7.5ms frames
        else:  # CVSD
            return 3.75  # CVSD typically uses 3.75ms
    
    def _calculate_mos(self, loss: float, latency: float, jitter: float) -> float:
        """Calculate Mean Opinion Score using simplified E-model"""
        # Base R-factor
        r_factor = 93.2
        
        # Impairment due to packet loss
        if loss > 0:
            r_factor -= 2.5 * np.log(1 + 10 * loss)
        
        # Impairment due to latency
        if latency > 150:
            r_factor -= (latency - 150) * 0.02
        
        # Impairment due to jitter
        r_factor -= jitter * 0.1
        
        # Convert R-factor to MOS
        if r_factor < 0:
            mos = 1.0
        elif r_factor > 100:
            mos = 4.5
        else:
            mos = 1 + 0.035 * r_factor + 0.000007 * r_factor * (r_factor - 60) * (100 - r_factor)
        
        return round(mos, 2)
    
    def _estimate_pesq(self, audio_data: bytes) -> float:
        """Estimate PESQ score (simplified)"""
        # In real implementation, would use actual PESQ algorithm
        # This is a simplified estimation based on signal characteristics
        
        if len(audio_data) < 160:  # Need at least 10ms of audio
            return 3.0
        
        # Convert bytes to audio samples
        samples = np.frombuffer(audio_data, dtype=np.int16)
        
        # Simple quality estimation based on signal variance
        variance = np.var(samples)
        if variance < 100:  # Very quiet, possibly muted
            return 1.0
        elif variance > 10000:  # Very loud, possibly clipping
            return 2.0
        else:
            # Map variance to PESQ-like score
            return 2.0 + min(2.5, variance / 4000)
    
    def _calculate_snr(self, audio_data: bytes) -> float:
        """Calculate signal-to-noise ratio"""
        if len(audio_data) < 320:
            return 20.0
        
        samples = np.frombuffer(audio_data, dtype=np.int16).astype(float)
        
        # Simple SNR estimation using high-frequency content as noise estimate
        fft = np.fft.fft(samples)
        signal_power = np.mean(np.abs(fft[:len(fft)//4])**2)
        noise_power = np.mean(np.abs(fft[3*len(fft)//4:])**2)
        
        if noise_power > 0:
            snr = 10 * np.log10(signal_power / noise_power)
            return max(0, min(50, snr))
        return 30.0
    
    def _detect_echo_likelihood(self, audio_data: bytes) -> float:
        """Detect likelihood of echo in audio"""
        if len(audio_data) < 640:  # Need 40ms for echo detection
            return 0.0
        
        samples = np.frombuffer(audio_data, dtype=np.int16).astype(float)
        
        # Simple echo detection using autocorrelation
        autocorr = np.correlate(samples, samples, mode='full')
        autocorr = autocorr[len(autocorr)//2:]
        
        # Look for peaks in autocorrelation at echo delays (10-50ms)
        echo_region = autocorr[160:800]  # 10-50ms at 16kHz
        
        if len(echo_region) > 0:
            echo_strength = np.max(echo_region) / np.max(autocorr)
            return min(1.0, echo_strength)
        return 0.0
    
    def _calculate_codec_efficiency(self, codec: str, loss: float, link_quality: int) -> float:
        """Calculate codec efficiency based on conditions"""
        base_efficiency = 0.9 if codec == "mSBC" else 0.8
        
        # Reduce efficiency based on packet loss
        efficiency = base_efficiency * (1 - loss)
        
        # Adjust for link quality
        if link_quality < 200:
            efficiency *= (link_quality / 255)
        
        return round(efficiency, 3)
    
    def _analyze_quality_trend(self) -> str:
        """Analyze quality trend over recent history"""
        if len(self.quality_history) < 10:
            return "stable"
        
        # Get recent MOS scores
        recent_scores = [m.mos_score for _, m in list(self.quality_history)[-30:]]
        
        if len(recent_scores) < 2:
            return "stable"
        
        # Calculate trend
        x = np.arange(len(recent_scores))
        slope, _ = np.polyfit(x, recent_scores, 1)
        
        if slope > 0.01:
            return "improving"
        elif slope < -0.01:
            return "degrading"
        else:
            return "stable"
    
    def _predict_failure(self) -> float:
        """Predict probability of connection failure using ML"""
        if not self.model_trained or len(self.quality_history) < 10:
            return 0.0
        
        # Extract features from recent history
        features = self._extract_ml_features()
        
        # Predict anomaly
        anomaly_score = self.anomaly_detector.decision_function([features])[0]
        
        # Convert to probability (sigmoid)
        probability = 1 / (1 + np.exp(anomaly_score))
        
        return round(probability, 3)
    
    def _estimate_time_to_failure(self) -> Optional[float]:
        """Estimate time until connection failure"""
        if not self.model_trained or len(self.quality_history) < 30:
            return None
        
        # Get failure probability trend
        recent_probs = []
        for _, metrics in list(self.quality_history)[-30:]:
            if metrics.failure_probability > 0:
                recent_probs.append(metrics.failure_probability)
        
        if len(recent_probs) < 10:
            return None
        
        # Fit exponential trend
        x = np.arange(len(recent_probs))
        y = np.array(recent_probs)
        
        if np.max(y) < 0.5:  # Not approaching failure
            return None
        
        # Simple linear extrapolation to failure threshold (0.8)
        slope, intercept = np.polyfit(x, y, 1)
        
        if slope <= 0:  # Not increasing
            return None
        
        # Time until probability reaches 0.8
        time_to_threshold = (0.8 - y[-1]) / slope
        
        return max(0, time_to_threshold * 60)  # Convert to seconds
    
    def _extract_ml_features(self) -> List[float]:
        """Extract features for ML model"""
        recent_metrics = [m for _, m in list(self.quality_history)[-60:]]
        
        if not recent_metrics:
            return [0] * 20
        
        features = []
        
        # Statistical features
        features.extend([
            np.mean([m.packet_loss_rate for m in recent_metrics]),
            np.std([m.packet_loss_rate for m in recent_metrics]),
            np.mean([m.average_latency for m in recent_metrics]),
            np.std([m.average_latency for m in recent_metrics]),
            np.mean([m.jitter for m in recent_metrics]),
            np.max([m.latency_p99 for m in recent_metrics]),
            np.mean([m.mos_score for m in recent_metrics]),
            np.min([m.mos_score for m in recent_metrics]),
            np.mean([m.signal_to_noise for m in recent_metrics]),
            np.mean([m.echo_likelihood for m in recent_metrics]),
        ])
        
        # Trend features
        if len(recent_metrics) > 1:
            mos_values = [m.mos_score for m in recent_metrics]
            x = np.arange(len(mos_values))
            slope, _ = np.polyfit(x, mos_values, 1)
            features.append(slope)
        else:
            features.append(0)
        
        # Recent changes
        if len(recent_metrics) > 10:
            recent = recent_metrics[-5:]
            older = recent_metrics[-15:-10]
            
            features.extend([
                np.mean([m.packet_loss_rate for m in recent]) - np.mean([m.packet_loss_rate for m in older]),
                np.mean([m.average_latency for m in recent]) - np.mean([m.average_latency for m in older]),
                np.mean([m.jitter for m in recent]) - np.mean([m.jitter for m in older]),
            ])
        else:
            features.extend([0, 0, 0])
        
        # Codec-related
        features.extend([
            self.codec_switches,
            recent_metrics[-1].codec_efficiency,
        ])
        
        # Ensure we have exactly 20 features
        while len(features) < 20:
            features.append(0)
        
        return features[:20]
    
    def train_model(self, historical_data: List[Tuple[List[float], bool]]):
        """Train ML model on historical data"""
        if len(historical_data) < 100:
            logger.warning("Insufficient data for training")
            return
        
        X = [features for features, _ in historical_data]
        y = [1 if failed else 0 for _, failed in historical_data]
        
        # Scale features
        X_scaled = self.scaler.fit_transform(X)
        
        # Train anomaly detector on normal data
        X_normal = [x for x, label in zip(X_scaled, y) if label == 0]
        if X_normal:
            self.anomaly_detector.fit(X_normal)
            self.model_trained = True
            logger.info("ML model trained successfully")
    
    def save_model(self, path: str):
        """Save trained model"""
        if self.model_trained:
            joblib.dump({
                'scaler': self.scaler,
                'anomaly_detector': self.anomaly_detector
            }, path)
            logger.info(f"Model saved to {path}")
    
    def load_model(self, path: str):
        """Load trained model"""
        try:
            model_data = joblib.load(path)
            self.scaler = model_data['scaler']
            self.anomaly_detector = model_data['anomaly_detector']
            self.model_trained = True
            logger.info(f"Model loaded from {path}")
        except Exception as e:
            logger.error(f"Failed to load model: {e}")
    
    def get_summary_report(self) -> Dict[str, any]:
        """Get comprehensive quality summary"""
        if not self.quality_history:
            return {"status": "No data available"}
        
        recent_metrics = [m for _, m in list(self.quality_history)[-300:]]  # Last 5 minutes
        
        return {
            "summary": {
                "total_packets": self.total_packets,
                "monitoring_duration": (datetime.now() - self.quality_history[0][0]).total_seconds(),
                "current_codec": self.last_codec,
                "codec_switches": self.codec_switches,
            },
            "quality_scores": {
                "current_mos": recent_metrics[-1].mos_score if recent_metrics else 0,
                "average_mos": np.mean([m.mos_score for m in recent_metrics]),
                "min_mos": np.min([m.mos_score for m in recent_metrics]),
                "trend": recent_metrics[-1].quality_trend if recent_metrics else "unknown",
            },
            "network_metrics": {
                "packet_loss_rate": np.mean([m.packet_loss_rate for m in recent_metrics]),
                "average_latency": np.mean([m.average_latency for m in recent_metrics]),
                "latency_p95": np.percentile([m.latency_p95 for m in recent_metrics], 95),
                "jitter": np.mean([m.jitter for m in recent_metrics]),
            },
            "audio_quality": {
                "average_snr": np.mean([m.signal_to_noise for m in recent_metrics]),
                "echo_detection": np.max([m.echo_likelihood for m in recent_metrics]),
                "codec_efficiency": np.mean([m.codec_efficiency for m in recent_metrics]),
            },
            "predictions": {
                "failure_probability": recent_metrics[-1].failure_probability if recent_metrics else 0,
                "time_to_failure": recent_metrics[-1].estimated_time_to_failure if recent_metrics else None,
                "recommended_action": self._get_recommended_action(recent_metrics[-1] if recent_metrics else None),
            }
        }
    
    def _get_recommended_action(self, metrics: Optional[AudioQualityMetrics]) -> str:
        """Get recommended action based on current metrics"""
        if not metrics:
            return "Continue monitoring"
        
        if metrics.failure_probability > 0.7:
            return "Immediate intervention required - reconnect recommended"
        elif metrics.failure_probability > 0.5:
            if metrics.codec_switches > 5:
                return "Force CVSD codec to stabilize connection"
            elif metrics.average_latency > 50:
                return "Check network congestion or interference"
            else:
                return "Monitor closely - connection degrading"
        elif metrics.mos_score < 3.0:
            if metrics.echo_likelihood > 0.5:
                return "Enable echo cancellation"
            elif metrics.signal_to_noise < 15:
                return "Check microphone placement or gain settings"
            else:
                return "Adjust audio settings for better quality"
        else:
            return "Connection stable - continue monitoring"
    
    def _default_metrics(self) -> AudioQualityMetrics:
        """Return default metrics when insufficient data"""
        return AudioQualityMetrics(
            packet_loss_rate=0.0,
            average_latency=0.0,
            latency_p95=0.0,
            latency_p99=0.0,
            jitter=0.0,
            jitter_variance=0.0,
            mos_score=4.0,
            pesq_score=3.5,
            signal_to_noise=30.0,
            echo_likelihood=0.0,
            failure_probability=0.0,
            quality_trend="stable",
            estimated_time_to_failure=None,
            codec_switches=0,
            codec_efficiency=1.0
        )

# Example usage
async def monitor_sco_connection():
    """Example SCO monitoring with predictive analytics"""
    monitor = AdvancedSCOMonitor()
    
    # Simulate SCO packets
    seq = 0
    while True:
        # Create simulated packet
        packet = SCOPacketInfo(
            timestamp=datetime.now(),
            sequence_number=seq,
            payload_size=60,
            rssi=-45 + np.random.randint(-10, 10),
            link_quality=200 + np.random.randint(-20, 20),
            error_rate=0.01 * np.random.random(),
            codec_type="mSBC" if seq % 100 < 80 else "CVSD",
            raw_data=bytes(np.random.randint(0, 255, 60))
        )
        
        # Process packet
        metrics = monitor.process_sco_packet(packet)
        
        # Log interesting events
        if metrics.failure_probability > 0.5:
            logger.warning(f"High failure probability: {metrics.failure_probability}")
        
        if seq % 100 == 0:
            summary = monitor.get_summary_report()
            logger.info(f"Quality summary: {summary}")
        
        seq += 1
        await asyncio.sleep(0.0075)  # 7.5ms per packet

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(monitor_sco_connection())