#!/bin/bash

# Build script for EventViewerMac Universal Binary
# Supports both Intel (x86_64) and Apple Silicon (arm64)

set -e

echo "Building EventViewerMac for Release..."
echo "Target architectures: x86_64 and arm64"

# Clean previous builds
rm -rf build/

# Build the app
xcodebuild -project EventViewerMac.xcodeproj \
    -scheme EventViewerMac \
    -configuration Release \
    -derivedDataPath ./build \
    ARCHS="x86_64 arm64" \
    ONLY_ACTIVE_ARCH=NO \
    clean build

# Verify architectures
APP_PATH="./build/Build/Products/Release/EventViewerMac.app"
BINARY_PATH="$APP_PATH/Contents/MacOS/EventViewerMac"

if [ -f "$BINARY_PATH" ]; then
    echo ""
    echo "Build successful!"
    echo "Verifying architectures..."
    lipo -info "$BINARY_PATH"
    
    # Create distributable zip
    cd build/Build/Products/Release
    zip -r EventViewerMac.zip EventViewerMac.app
    cd -
    
    echo ""
    echo "Distribution package created: build/Build/Products/Release/EventViewerMac.zip"
else
    echo "Build failed - binary not found"
    exit 1
fi
