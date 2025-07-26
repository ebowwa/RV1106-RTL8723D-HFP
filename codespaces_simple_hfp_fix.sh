#!/bin/bash
# Simple HFP fix using pre-built packages or PipeWire

echo "=== Simple HFP Fix for RV1106 ==="
echo ""
echo "Since oFono build requires complex dependencies, here are alternatives:"
echo ""

# Option 1: Download pre-built oFono
cat > download_prebuilt_ofono.sh << 'EOF'
#!/bin/bash
# Download pre-built ARM packages

echo "Option 1: Pre-built packages"
echo ""

# Try to find pre-built oFono for ARM
mkdir -p ~/prebuilt
cd ~/prebuilt

# Debian/Ubuntu ARM packages
echo "Downloading ARM packages..."
wget http://ports.ubuntu.com/pool/main/o/ofono/ofono_1.34-1_armhf.deb
wget http://ports.ubuntu.com/pool/main/libd/libdbus-1-3/libdbus-1-3_1.14.10-1ubuntu1_armhf.deb

# Extract without installing
dpkg-deb -x ofono_1.34-1_armhf.deb ofono-extract/
dpkg-deb -x libdbus-1-3_1.14.10-1ubuntu1_armhf.deb libs-extract/

# Create package
cd ofono-extract
tar -czf ~/ofono-prebuilt-arm.tar.gz *

echo "Created: ~/ofono-prebuilt-arm.tar.gz"
EOF

# Option 2: Use PipeWire (modern approach)
cat > pipewire_bluetooth_solution.sh << 'EOF'
#!/bin/bash
# PipeWire handles both A2DP and HFP properly

echo "Option 2: PipeWire Solution"
echo ""
echo "PipeWire is the modern replacement for PulseAudio/BlueALSA"
echo "It has proper HFP support built-in"
echo ""

# For RV1106, you would need:
# 1. PipeWire core
# 2. PipeWire-pulse (PulseAudio compatibility)
# 3. WirePlumber (session manager)
# 4. libspa-bluetooth (Bluetooth plugin)

cat > install_pipewire.txt << 'PIPEWIRE'
To use PipeWire on RV1106:

1. In your build system (Buildroot/Yocto):
   - Enable BR2_PACKAGE_PIPEWIRE
   - Enable BR2_PACKAGE_WIREPLUMBER
   - Enable Bluetooth support

2. Configuration:
   /etc/pipewire/pipewire.conf
   /etc/wireplumber/bluetooth.lua.d/

3. Run:
   pipewire &
   wireplumber &

PipeWire automatically handles:
- A2DP (music)
- HFP/HSP (calls)
- Codec negotiation
- Audio routing
PIPEWIRE

echo "See install_pipewire.txt for details"
EOF

# Option 3: Fix BlueALSA HFP
cat > fix_bluealsa_hfp.sh << 'EOF'
#!/bin/bash
# Workaround for BlueALSA HFP issues

echo "Option 3: BlueALSA Workarounds"
echo ""

cat > bluealsa_hfp_config.txt << 'CONFIG'
BlueALSA HFP Workarounds:

1. Use HFP-AG mode (server) instead of HFP-HF (client):
   bluealsa -p hfp-ag -p a2dp-sink &
   # Device acts as "phone" not "headset"

2. Disable codec negotiation:
   bluealsa --hfp-ag-codec=CVSD &
   # Forces CVSD, avoids mSBC issues

3. Use SCO routing fix:
   hcitool cmd 0x3f 0x1c 0x01 0x00 0x00 0x00
   # Route SCO over HCI

4. AT command fixes:
   # Create /etc/bluealsa/hfp-ag.conf
   AT+BRSF=0x1FF
   AT+CIND=?
   AT+CIND?
   AT+CMER=3,0,0,1

5. Alternative: Use hsphfpd
   # Separate daemon for HSP/HFP
   https://github.com/benzea/hsphfpd
CONFIG

echo "See bluealsa_hfp_config.txt for workarounds"
EOF

# Summary
echo ""
echo "=== HFP Fix Options ==="
echo ""
echo "1. Pre-built oFono:"
echo "   ./download_prebuilt_ofono.sh"
echo ""
echo "2. PipeWire (recommended for new systems):"
echo "   ./pipewire_bluetooth_solution.sh"
echo ""
echo "3. BlueALSA workarounds:"
echo "   ./fix_bluealsa_hfp.sh"
echo ""
echo "For your RV1106 with the 'Too small packet' error,"
echo "the issue is BlueALSA's HFP-HF implementation."
echo ""
echo "Quick fix: Use BlueALSA in HFP-AG mode:"
echo "bluealsa -p hfp-ag -p a2dp-sink &"

chmod +x *.sh