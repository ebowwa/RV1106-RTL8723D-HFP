#!/bin/bash
# Setup script for RV1106-RTL8723D-Project

echo "🔧 RV1106 + RTL8723D Project Setup"
echo "=================================="
echo ""

# Initialize git repository
if [ ! -d .git ]; then
    echo "Initializing git repository..."
    git init
    git add .
    git commit -m "Initial commit: RV1106 + RTL8723D HFP solution"
fi

# Create GitHub repository
echo -e "\n📦 Creating GitHub repository..."
echo "Run these commands to create and push to GitHub:"
echo ""
echo "gh repo create RV1106-RTL8723D-HFP --public --description 'Solution for RTL8723D HFP issues on RV1106' --source=. --remote=origin --push"
echo ""
echo "Or manually:"
echo "1. Create repo on GitHub: https://github.com/new"
echo "2. git remote add origin https://github.com/YOUR_USERNAME/RV1106-RTL8723D-HFP.git"
echo "3. git push -u origin main"
echo ""

# Setup instructions
echo -e "\n🚀 Quick Start:"
echo "1. Open in GitHub Codespace or clone locally"
echo "2. Build rtk_hciattach:"
echo "   cd tools/rtk_hciattach && ./build.sh"
echo "3. Deploy to device:"
echo "   cd RV1106-BlueFusion-HFP && ./deploy.sh"
echo ""

# Check for dependencies
echo -e "\n📋 Checking local environment..."
if command -v adb &> /dev/null; then
    echo "✓ ADB installed"
    adb devices
else
    echo "❌ ADB not found - install Android platform tools"
fi

if command -v python3 &> /dev/null; then
    echo "✓ Python3 installed"
else
    echo "❌ Python3 not found"
fi

if command -v docker &> /dev/null; then
    echo "✓ Docker installed"
else
    echo "⚠️  Docker not found (optional for macOS builds)"
fi

echo -e "\n✅ Setup complete!"
echo "Next: Push to GitHub and use Codespace for ARM compilation"