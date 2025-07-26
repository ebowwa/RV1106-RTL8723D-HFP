#\!/bin/bash
# Compile rtk_hciattach for ARM as instructed by user

echo "Setting up cross-compilation for rtk_hciattach..."

# Check if cross-compiler is installed
if \! command -v arm-linux-gnueabihf-gcc &> /dev/null; then
    echo "Installing ARM cross-compiler..."
    # On macOS, we need to use a different approach
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macOS detected. Need to use Docker for cross-compilation."
        
        # Create Dockerfile for cross-compilation
        cat > Dockerfile.arm << 'DOCKERFILE'
FROM arm32v7/ubuntu:20.04

RUN apt-get update && apt-get install -y \
    gcc \
    make \
    libc6-dev

WORKDIR /build
DOCKERFILE

        # Build and run
        docker build -f Dockerfile.arm -t arm-builder .
        docker run --rm -v $PWD/rtk_hciattach:/build arm-builder sh -c "cd /build && make clean && make"
        
        if [ -f rtk_hciattach/rtk_hciattach ]; then
            echo "✓ Compilation successful\!"
            echo "Binary at: rtk_hciattach/rtk_hciattach"
            
            # Push to device
            adb push rtk_hciattach/rtk_hciattach /tmp/
            adb shell "chmod +x /tmp/rtk_hciattach"
            echo "✓ Pushed to device at /tmp/rtk_hciattach"
        fi
    else
        # Linux - install cross-compiler
        sudo apt-get update
        sudo apt-get install -y gcc-arm-linux-gnueabihf
    fi
fi

# If not using Docker, compile directly
if command -v arm-linux-gnueabihf-gcc &> /dev/null; then
    cd rtk_hciattach
    
    # Modify Makefile to use cross-compiler
    sed -i.bak 's/cc/arm-linux-gnueabihf-gcc/g' Makefile
    
    # Clean and build
    make clean
    make
    
    if [ -f rtk_hciattach ]; then
        echo "✓ Cross-compilation successful\!"
        file rtk_hciattach
        
        # Push to device
        adb push rtk_hciattach /tmp/
        adb shell "chmod +x /tmp/rtk_hciattach"
        echo "✓ Pushed to device"
    fi
fi

echo -e "\nTo test on device:"
echo "adb shell '/tmp/rtk_hciattach -n -s 115200 /dev/ttyS5 rtk_h5'"
