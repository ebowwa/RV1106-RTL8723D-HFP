"""
Classic Bluetooth API Routes for BlueFusion
Extends the FastAPI server with Classic Bluetooth capabilities
"""

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from typing import List, Dict, Any, Optional
from datetime import datetime
import asyncio
import json

from ..classic import ClassicBluetoothAdapter, HFPProtocolHandler, SCOAudioAnalyzer
from ..interfaces.classic_base import ClassicDevice, ClassicProfile, AudioCodec, HFPConnection
from ..unified_monitor import UnifiedBluetoothMonitor

# Create router
router = APIRouter(prefix="/api/classic", tags=["Classic Bluetooth"])

# Global instances (will be initialized by main app)
classic_adapter: Optional[ClassicBluetoothAdapter] = None
unified_monitor: Optional[UnifiedBluetoothMonitor] = None
hfp_handlers: Dict[str, HFPProtocolHandler] = {}

@router.get("/status")
async def get_classic_status():
    """Get Classic Bluetooth adapter status"""
    if not classic_adapter:
        raise HTTPException(status_code=503, detail="Classic Bluetooth not initialized")
    
    return {
        "initialized": True,
        "active_connections": len(classic_adapter.hfp_connections),
        "has_sco": classic_adapter.has_active_sco()
    }

@router.get("/devices")
async def scan_classic_devices(duration: int = 10):
    """Scan for Classic Bluetooth devices"""
    if not classic_adapter:
        raise HTTPException(status_code=503, detail="Classic Bluetooth not initialized")
    
    devices = await classic_adapter.scan_classic_devices(duration)
    
    return {
        "devices": [
            {
                "address": device.address,
                "name": device.name,
                "device_class": device.device_class,
                "profiles": device.profiles,
                "rssi": device.rssi
            }
            for device in devices
        ],
        "count": len(devices),
        "scan_duration": duration
    }

@router.post("/hfp/connect")
async def connect_hfp(address: str, role: str = "HF"):
    """Connect to HFP device"""
    if not classic_adapter:
        raise HTTPException(status_code=503, detail="Classic Bluetooth not initialized")
    
    if role not in ["HF", "AG"]:
        raise HTTPException(status_code=400, detail="Role must be 'HF' or 'AG'")
    
    # Create HFP handler for this device
    if address not in hfp_handlers:
        hfp_handlers[address] = HFPProtocolHandler()
    
    # Connect
    connection = await classic_adapter.connect_hfp(address)
    if not connection:
        raise HTTPException(status_code=500, detail="Failed to connect HFP")
    
    return {
        "connection_id": connection.id,
        "device": {
            "address": connection.device.address,
            "name": connection.device.name
        },
        "state": connection.state,
        "codec": connection.codec
    }

@router.post("/hfp/{connection_id}/sco")
async def connect_sco(connection_id: str):
    """Establish SCO audio connection"""
    if not classic_adapter:
        raise HTTPException(status_code=503, detail="Classic Bluetooth not initialized")
    
    success = await classic_adapter.connect_sco(connection_id)
    if not success:
        raise HTTPException(status_code=500, detail="Failed to establish SCO connection")
    
    return {"status": "SCO connected", "connection_id": connection_id}

@router.get("/hfp/{connection_id}/status")
async def get_hfp_status(connection_id: str):
    """Get HFP connection status"""
    if not classic_adapter:
        raise HTTPException(status_code=503, detail="Classic Bluetooth not initialized")
    
    stats = classic_adapter.get_connection_stats(connection_id)
    if not stats:
        raise HTTPException(status_code=404, detail="Connection not found")
    
    return stats

@router.post("/hfp/{connection_id}/at")
async def send_at_command(connection_id: str, command: str):
    """Send AT command to HFP device"""
    if not classic_adapter:
        raise HTTPException(status_code=503, detail="Classic Bluetooth not initialized")
    
    connection = classic_adapter.hfp_connections.get(connection_id)
    if not connection:
        raise HTTPException(status_code=404, detail="Connection not found")
    
    # Get HFP handler
    handler = hfp_handlers.get(connection.device.address)
    if handler:
        handler.process_at_command(command, direction="TX")
    
    # In real implementation, send command through RFCOMM
    # For now, return simulated response
    return {
        "command": command,
        "response": "OK",
        "timestamp": datetime.now().isoformat()
    }

@router.get("/hfp/{address}/analysis")
async def analyze_hfp_failure(address: str):
    """Analyze HFP connection issues for a device"""
    if address not in hfp_handlers:
        raise HTTPException(status_code=404, detail="No HFP data for this device")
    
    handler = hfp_handlers[address]
    analysis = handler.analyze_failure()
    
    return analysis

@router.post("/hfp/{connection_id}/disconnect")
async def disconnect_hfp(connection_id: str):
    """Disconnect HFP connection"""
    if not classic_adapter:
        raise HTTPException(status_code=503, detail="Classic Bluetooth not initialized")
    
    await classic_adapter.disconnect(connection_id)
    
    return {"status": "disconnected", "connection_id": connection_id}

@router.get("/audio/analysis")
async def get_audio_analysis():
    """Get SCO audio quality analysis"""
    if not classic_adapter:
        raise HTTPException(status_code=503, detail="Classic Bluetooth not initialized")
    
    # Check if we have an active SCO connection
    if not classic_adapter.has_active_sco():
        raise HTTPException(status_code=404, detail="No active SCO connection")
    
    # Get SCO analyzer
    analyzer = SCOAudioAnalyzer()
    
    # In real implementation, analyze actual SCO stream
    # For now, return example analysis
    return {
        "codec": "mSBC",
        "quality_score": 85.5,
        "metrics": {
            "packet_loss_rate": 0.02,
            "average_latency": 12.5,
            "jitter": 1.8
        },
        "issues": [],
        "recommendations": []
    }

@router.websocket("/ws/monitor")
async def websocket_monitor(websocket: WebSocket):
    """WebSocket endpoint for real-time Classic Bluetooth monitoring"""
    await websocket.accept()
    
    try:
        while True:
            # Send updates every second
            if unified_monitor:
                status = unified_monitor.get_unified_status()
                await websocket.send_json({
                    "type": "status_update",
                    "timestamp": datetime.now().isoformat(),
                    "classic": status.get("classic", {})
                })
            
            await asyncio.sleep(1)
            
    except WebSocketDisconnect:
        pass
    except Exception as e:
        await websocket.close(code=1000, reason=str(e))

@router.post("/test/hfp/{address}")
async def test_hfp_connection(address: str):
    """Test complete HFP connection flow"""
    if not unified_monitor:
        raise HTTPException(status_code=503, detail="Unified monitor not initialized")
    
    result = await unified_monitor.test_hfp_connection(address)
    
    return result

# Helper function to initialize Classic Bluetooth
async def initialize_classic_bluetooth():
    """Initialize Classic Bluetooth components"""
    global classic_adapter, unified_monitor
    
    classic_adapter = ClassicBluetoothAdapter()
    
    # Create unified monitor config
    config = {
        "ble": {"enabled": True},
        "classic": {"enabled": True},
        "sniffer": {"enabled": False}
    }
    
    unified_monitor = UnifiedBluetoothMonitor(config)
    await unified_monitor.initialize()
    
    return classic_adapter, unified_monitor