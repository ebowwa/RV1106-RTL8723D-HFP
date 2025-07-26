#!/bin/bash
# BlueFusion Classic Bluetooth Setup Script
# Automates the setup process for RV1106 + RTL8723D

set -e

echo "================================================"
echo "BlueFusion Classic Bluetooth Setup"
echo "================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
   print_error "Please do not run this script as root"
   exit 1
fi

# Step 1: Install system dependencies
print_status "Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    git \
    python3-pip \
    python3-dev \
    libbluetooth-dev \
    bluetooth \
    bluez \
    bluez-tools \
    libasound2-dev \
    libdbus-1-dev \
    libglib2.0-dev \
    libsbc-dev \
    libusb-1.0-0-dev \
    automake \
    libtool \
    pkg-config

# Step 2: Install rkdeveloptool
print_status "Installing rkdeveloptool..."
if ! command -v rkdeveloptool &> /dev/null; then
    cd /tmp
    git clone https://github.com/rockchip-linux/rkdeveloptool.git
    cd rkdeveloptool
    autoreconf -i
    ./configure
    make
    sudo make install
    cd -
    print_status "rkdeveloptool installed successfully"
else
    print_warning "rkdeveloptool already installed"
fi

# Step 3: Check for RV1106 device
print_status "Checking for RV1106 device..."
if sudo rkdeveloptool ld | grep -q "Maskrom\|Loader"; then
    print_status "RV1106 device detected"
    sudo rkdeveloptool ld
else
    print_error "No RV1106 device detected. Please check USB connection."
    print_warning "Continue anyway? (y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Step 4: Install Python dependencies
print_status "Installing Python dependencies..."
pip3 install --user \
    bleak>=0.21.0 \
    pyserial>=3.5 \
    pydantic>=2.0 \
    rich>=13.0 \
    numpy>=1.24.0 \
    pandas>=2.0.0 \
    aiofiles>=23.0 \
    structlog>=23.0 \
    click>=8.1.0 \
    fastapi>=0.100.0 \
    "uvicorn[standard]>=0.23.0" \
    websockets>=11.0 \
    gradio>=4.0.0 \
    httpx>=0.25.0 \
    plotly>=5.17.0

# Try to install PyBluez
print_status "Installing PyBluez..."
if pip3 install --user pybluez==0.23; then
    print_status "PyBluez installed successfully"
else
    print_warning "PyBluez installation failed, trying from git..."
    pip3 install --user git+https://github.com/pybluez/pybluez.git || \
    print_warning "PyBluez installation failed. Classic Bluetooth will use hcitool fallback."
fi

# Install PyAudio
print_status "Installing PyAudio..."
pip3 install --user pyaudio || print_warning "PyAudio installation failed"

# Step 5: Install BlueALSA (optional but recommended)
print_status "Checking for BlueALSA..."
if ! command -v bluealsa &> /dev/null; then
    print_warning "BlueALSA not found. Install it? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        cd /tmp
        git clone https://github.com/Arkq/bluez-alsa.git
        cd bluez-alsa
        autoreconf -fi
        ./configure --enable-hfp --enable-msbc --enable-debug
        make
        sudo make install
        cd -
        print_status "BlueALSA installed"
    fi
else
    print_status "BlueALSA already installed"
fi

# Step 6: Create test script symlink
print_status "Setting up test scripts..."
chmod +x test_rv1106_hfp.py

# Step 7: Verify installation
print_status "Verifying installation..."
echo ""
echo "Installation Summary:"
echo "--------------------"

# Check each component
if command -v rkdeveloptool &> /dev/null; then
    echo "✓ rkdeveloptool: $(rkdeveloptool -v 2>&1 | head -1)"
else
    echo "✗ rkdeveloptool: NOT FOUND"
fi

if command -v bluetoothctl &> /dev/null; then
    echo "✓ BlueZ: $(bluetoothctl --version)"
else
    echo "✗ BlueZ: NOT FOUND"
fi

if command -v bluealsa &> /dev/null; then
    echo "✓ BlueALSA: Installed"
else
    echo "! BlueALSA: Not installed (optional)"
fi

if python3 -c "import bluetooth" 2>/dev/null; then
    echo "✓ PyBluez: Installed"
else
    echo "! PyBluez: Not installed (will use hcitool)"
fi

echo ""
print_status "Setup complete!"
echo ""
echo "Next steps:"
echo "1. Connect your RV1106 device via USB-C"
echo "2. Run the HFP test:"
echo "   python3 test_rv1106_hfp.py YOUR_PHONE_MAC_ADDRESS"
echo ""
echo "For monitoring mode:"
echo "   python3 test_rv1106_hfp.py --monitor"
echo ""
echo "For API usage:"
echo "   python3 -m src.api.fastapi_server"
echo ""
echo "See CLASSIC_BLUETOOTH_SETUP.md for detailed documentation."