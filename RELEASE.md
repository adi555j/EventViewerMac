# Release Instructions

## Building the Release

Since Xcode is required to build the app, you'll need to build it manually:

### Option 1: Using the Build Script (Requires Xcode)

```bash
./build.sh
```

This will:
- Build a universal binary (x86_64 + arm64)
- Create `EventViewerMac.zip` in `build/Build/Products/Release/`

### Option 2: Using Xcode GUI

1. Open `EventViewerMac.xcodeproj` in Xcode
2. Select **Product > Archive**
3. Once archived, click **Distribute App**
4. Choose **Copy App** 
5. Save the app and create a zip file

## Creating a GitHub Release

### Option A: Using GitHub CLI (if installed)

```bash
# Install gh if needed
brew install gh

# Authenticate
gh auth login

# Create a release with the built app
gh release create v1.0.0 \
  build/Build/Products/Release/EventViewerMac.zip \
  --title "EventViewerMac v1.0.0 - Universal Binary" \
  --notes "## What's New

- Universal Binary support (Intel x86_64 + Apple Silicon arm64)
- Native macOS app for viewing Windows Event Log (.evtx) files
- SwiftUI-based interface
- Event details viewer with XML support

## System Requirements
- macOS 14.0 or later
- Works on both Intel and Apple Silicon Macs"
```

### Option B: Using GitHub Web Interface

1. Go to https://github.com/adi555j/EventViewerMac/releases/new
2. Create a new tag: `v1.0.0`
3. Set release title: **EventViewerMac v1.0.0 - Universal Binary**
4. Add release notes:

```markdown
## What's New

- Universal Binary support (Intel x86_64 + Apple Silicon arm64)
- Native macOS app for viewing Windows Event Log (.evtx) files
- SwiftUI-based interface
- Event details viewer with XML support

## System Requirements
- macOS 14.0 or later
- Works on both Intel and Apple Silicon Macs

## Installation

1. Download `EventViewerMac.zip`
2. Extract the zip file
3. Move `EventViewerMac.app` to your Applications folder
4. Right-click and select "Open" on first launch (due to Gatekeeper)
```

5. Upload the `EventViewerMac.zip` file from `build/Build/Products/Release/`
6. Click **Publish release**

## Verifying the Build

After building, verify it's a universal binary:

```bash
lipo -archs build/Build/Products/Release/EventViewerMac.app/Contents/MacOS/EventViewerMac
```

Expected output: `x86_64 arm64`
