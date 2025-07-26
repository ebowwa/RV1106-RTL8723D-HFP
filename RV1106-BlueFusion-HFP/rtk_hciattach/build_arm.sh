#\!/bin/sh
# Build rtk_hciattach for ARM

echo "Building rtk_hciattach..."

# Simple direct compilation
gcc -o rtk_hciattach hciattach.c hciattach_rtk.c \
    -DVERSION=\"1.0\" \
    -D_GNU_SOURCE \
    -Wall

if [ -f rtk_hciattach ]; then
    echo "Build successful\!"
    ls -la rtk_hciattach
else
    echo "Build failed"
fi
