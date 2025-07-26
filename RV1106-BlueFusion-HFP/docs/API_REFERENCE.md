# RV1106 HFP API Reference

## Base URL
```
http://localhost:8000
```

## Authentication
No authentication required for local use.

## Endpoints

### System Status

#### GET /
Get API status
```bash
curl http://localhost:8000/
```

Response:
```json
{
  "service": "RV1106 HFP API",
  "status": "running",
  "endpoints": {
    "status": "/api/classic/status",
    "devices": "/api/classic/devices",
    "docs": "/docs"
  }
}
```

### Classic Bluetooth Operations

#### GET /api/classic/status
Get Classic Bluetooth adapter status

Response:
```json
{
  "initialized": true,
  "active_connections": 1,
  "has_sco": false
}
```

#### GET /api/classic/devices
Scan for Classic Bluetooth devices

Query Parameters:
- `duration` (int, optional): Scan duration in seconds (default: 10)

Response:
```json
{
  "devices": [
    {
      "address": "E8:D5:2B:13:B5:AB",
      "name": "iPhone",
      "device_class": 5898764,
      "profiles": ["HFP", "A2DP", "AVRCP"],
      "rssi": -45
    }
  ],
  "count": 1,
  "scan_duration": 10
}
```

### HFP Operations

#### POST /api/classic/hfp/connect
Connect to HFP device

Request Body:
```json
{
  "address": "E8:D5:2B:13:B5:AB",
  "role": "HF"
}
```

Response:
```json
{
  "connection_id": "hfp_E8D52B13B5AB_1234567890",
  "device": {
    "address": "E8:D5:2B:13:B5:AB",
    "name": "iPhone"
  },
  "state": "CONNECTING",
  "codec": "CVSD"
}
```

#### GET /api/classic/hfp/{connection_id}/status
Get HFP connection status

Response:
```json
{
  "id": "hfp_E8D52B13B5AB_1234567890",
  "device": {
    "address": "E8:D5:2B:13:B5:AB",
    "name": "iPhone",
    "profiles": ["HFP", "A2DP"]
  },
  "state": "CONNECTED",
  "codec": "mSBC",
  "features": {
    "codec_negotiation": true,
    "wideband_speech": true
  },
  "rfcomm_connected": true,
  "sco_connected": false
}
```

#### POST /api/classic/hfp/{connection_id}/sco
Establish SCO audio connection

Response:
```json
{
  "status": "SCO connected",
  "connection_id": "hfp_E8D52B13B5AB_1234567890"
}
```

#### POST /api/classic/hfp/{connection_id}/at
Send AT command

Request Body:
```json
{
  "command": "AT+BRSF=254"
}
```

Response:
```json
{
  "command": "AT+BRSF=254",
  "response": "OK",
  "timestamp": "2024-07-25T16:45:00.123456"
}
```

#### GET /api/classic/hfp/{address}/analysis
Analyze HFP connection failures

Response:
```json
{
  "last_state": "SLC_CONNECTING",
  "total_commands": 15,
  "features": {
    "codec_negotiation": true,
    "selected_codec": "CVSD",
    "supported_codecs": ["CVSD", "mSBC"]
  },
  "likely_issues": [
    "Codec negotiation incomplete",
    "SCO audio connection failed"
  ],
  "command_flow": [
    {
      "time": 0.0,
      "command": "AT+BRSF=254",
      "direction": "TX",
      "state": "SLC_CONNECTING"
    }
  ]
}
```

#### POST /api/classic/hfp/{connection_id}/disconnect
Disconnect HFP connection

Response:
```json
{
  "status": "disconnected",
  "connection_id": "hfp_E8D52B13B5AB_1234567890"
}
```

### Audio Analysis

#### GET /api/classic/audio/analysis
Get SCO audio quality analysis

Response:
```json
{
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
```

### Testing

#### POST /api/classic/test/hfp/{address}
Run complete HFP connection test

Response:
```json
{
  "address": "E8:D5:2B:13:B5:AB",
  "timestamp": "2024-07-25T16:45:00.123456",
  "success": true,
  "steps": [
    {
      "step": "HFP Connect",
      "status": "success",
      "connection_id": "hfp_E8D52B13B5AB_1234567890"
    },
    {
      "step": "SCO Setup",
      "status": "success"
    },
    {
      "step": "Audio Analysis",
      "status": "success"
    }
  ],
  "audio_metrics": {
    "codec": "mSBC",
    "quality_score": 92.3,
    "packet_loss": 0.01,
    "latency": 10.2,
    "jitter": 1.5
  }
}
```

## WebSocket Endpoints

### WS /api/classic/ws/monitor
Real-time Classic Bluetooth monitoring

Connect:
```javascript
const ws = new WebSocket('ws://localhost:8000/api/classic/ws/monitor');
```

Message Format:
```json
{
  "type": "status_update",
  "timestamp": "2024-07-25T16:45:00.123456",
  "classic": {
    "devices": 2,
    "hfp_handlers": 1,
    "active_sco": true,
    "statistics": {
      "packets_captured": 1234,
      "devices_discovered": 2,
      "hfp_connections": 1,
      "sco_connections": 1
    }
  }
}
```

## Error Responses

All endpoints return standard HTTP status codes:

- `200 OK` - Success
- `400 Bad Request` - Invalid parameters
- `404 Not Found` - Resource not found
- `500 Internal Server Error` - Server error
- `503 Service Unavailable` - Service not initialized

Error Response Format:
```json
{
  "detail": "Error message describing what went wrong"
}
```

## Examples

### Complete HFP Test Flow
```bash
# 1. Check status
curl http://localhost:8000/api/classic/status

# 2. Scan for devices
curl "http://localhost:8000/api/classic/devices?duration=10"

# 3. Connect HFP
curl -X POST http://localhost:8000/api/classic/hfp/connect \
  -H "Content-Type: application/json" \
  -d '{"address": "E8:D5:2B:13:B5:AB", "role": "HF"}'

# 4. Get connection ID from response, then check status
curl http://localhost:8000/api/classic/hfp/hfp_E8D52B13B5AB_1234567890/status

# 5. Establish SCO
curl -X POST http://localhost:8000/api/classic/hfp/hfp_E8D52B13B5AB_1234567890/sco

# 6. Get audio analysis
curl http://localhost:8000/api/classic/audio/analysis

# 7. Disconnect when done
curl -X POST http://localhost:8000/api/classic/hfp/hfp_E8D52B13B5AB_1234567890/disconnect
```

### Monitor with WebSocket
```javascript
const ws = new WebSocket('ws://localhost:8000/api/classic/ws/monitor');

ws.onopen = () => {
  console.log('Connected to monitor');
};

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Status update:', data);
};

ws.onerror = (error) => {
  console.error('WebSocket error:', error);
};
```