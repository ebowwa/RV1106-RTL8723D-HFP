#\!/bin/bash
# Build rtk_hciattach using Docker

echo "Building rtk_hciattach with Docker..."

# Start Docker if not running
if \! docker info &> /dev/null; then
    echo "Starting Docker..."
    open -a Docker
    echo "Waiting for Docker to start..."
    sleep 10
fi

# Build using ARM container
docker run --rm -v $PWD:/src arm32v7/gcc:9 bash -c '
cd /src
echo "Compiling rtk_hciattach for ARM..."
gcc -static -Wall -O2 -o rtk_hciattach hciattach.c hciattach_rtk.c
if [ -f rtk_hciattach ]; then
    echo "✓ Build successful\!"
    file rtk_hciattach
    ls -la rtk_hciattach
else
    echo "✗ Build failed"
fi
'
