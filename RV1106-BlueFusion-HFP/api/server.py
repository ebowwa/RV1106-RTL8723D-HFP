#!/usr/bin/env python3
"""
RV1106 HFP API Server
Minimal FastAPI server for Classic Bluetooth HFP control
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import sys
import os

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from api.classic_routes import router, initialize_classic_bluetooth

# Create FastAPI app
app = FastAPI(
    title="RV1106 HFP API",
    description="Control and monitor HFP connections on RV1106 devices",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include Classic Bluetooth routes
app.include_router(router)

@app.on_event("startup")
async def startup_event():
    """Initialize Classic Bluetooth on startup"""
    try:
        await initialize_classic_bluetooth()
        print("✅ Classic Bluetooth initialized")
    except Exception as e:
        print(f"⚠️ Classic Bluetooth initialization failed: {e}")

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "RV1106 HFP API",
        "status": "running",
        "endpoints": {
            "status": "/api/classic/status",
            "devices": "/api/classic/devices",
            "docs": "/docs"
        }
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)