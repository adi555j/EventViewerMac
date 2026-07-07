# EventViewerMac

A native macOS application for viewing Windows Event Log (.evtx) files.

## Features

- Parse and display Windows Event Log (.evtx) files
- Native macOS interface built with SwiftUI
- View event details including timestamps, event IDs, sources, and XML data
- Search and filter events

## System Requirements

- macOS 14.0 or later
- Universal Binary: Runs natively on both Intel and Apple Silicon Macs

## Building from Source

### Prerequisites

- Xcode 16.0 or later
- macOS 14.0 SDK or later

### Build Instructions

1. Clone the repository:
```bash
git clone https://github.com/adi555j/EventViewerMac.git
cd EventViewerMac
```

2. Build using the provided script:
```bash
./build.sh
```

Or build manually using Xcode:
- Open `EventViewerMac.xcodeproj` in Xcode
- Select Product > Archive
- Export the app

The built app will support both x86_64 (Intel) and arm64 (Apple Silicon) architectures.

### Verify Universal Binary

After building, verify the binary contains both architectures:
```bash
lipo -archs build/Build/Products/Release/EventViewerMac.app/Contents/MacOS/EventViewerMac
```

Expected output: `x86_64 arm64`

## Usage

1. Launch EventViewerMac
2. Click "Open EVTX File" to select a Windows Event Log file
3. Browse through the events in the list
4. Click on any event to view detailed information

## License

Copyright © 2026. All rights reserved.
