## VideoSzhimaka

A fast, native macOS app for batch video compression built with SwiftUI. It wraps a bundled FFmpeg binary with a friendly UI, drag-and-drop, detailed logging, and robust error handling.

- **Platform**: macOS (Apple Silicon only, arm64)
- **Minimum macOS**: 12.0 (Monterey)
- **Language/Frameworks**: Swift 5, SwiftUI, AppKit
- **Primary binary**: `FFmpeg` (bundled)

### Why VideoSzhimaka?
- **Batch compression**: Drop multiple videos and compress them at once
- **Simple UI**: Drag-and-drop, progress per file, quick actions
- **Safe by default**: Error surfacing, retry support, and log viewer
- **Tunable**: Compression settings, theme toggle, Dock/Menu Bar presence

---

## Requirements
- Mac with **Apple Silicon (M1/M2/M3)**. Intel Macs are not supported.
- macOS **12.0+**
- Xcode **14+** (recommended 15+)

The app enforces native Apple Silicon execution and will show an incompatibility alert on Intel/Rosetta.

---

## Getting Started

### Open in Xcode
1. Open `VideoSzhimaka.xcodeproj` in Xcode
2. Select the scheme: `VideoSzhimaka`
3. Choose a destination: `My Mac (Apple Silicon)`
4. Run (⌘R)

### Build via CLI
```bash
# Build the app
xcodebuild -scheme VideoSzhimaka \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  build

# Run unit and UI tests
xcodebuild test -scheme VideoSzhimaka \
  -destination 'platform=macOS,arch=arm64'
```

Notes:
- Deployment target: `macOS 12.0`
- Bundle identifier: `com.videoszhimaka.VideoSzhimaka`

---

## Usage
- Launch the app
- **Drag and drop** video files into the main window or click **Добавить файлы** (Add files)
- Adjust settings (gear icon or via menu bar item): output formats, performance and behavior toggles
- Click **Сжать всё** (Compress all)
- Open **Логи** (Logs) to inspect detailed FFmpeg output and errors if needed

The interface currently uses Russian labels (e.g., "Видео-Сжимака").

---

## FFmpeg and Licensing
The app bundles an FFmpeg binary for convenience.

- Location (runtime resource):
  - `VideoSzhimaka/Resources/bin/ffmpeg`
- License:
  - `VideoSzhimaka/Resources/LICENSES/FFmpeg_LICENSE.txt`

You may swap the bundled binary with your own build of FFmpeg if you need different codecs or configurations:
1. Replace the file at `VideoSzhimaka/Resources/bin/ffmpeg`
2. Ensure it is executable (`chmod +x`)
3. Rebuild the app in Xcode

When distributing the app, ensure compliance with FFmpeg’s license terms that apply to your chosen build/configuration.

---

## Project Structure
```
VideoSzhimaka/
  Models/                  # Video domain models and states
  Views/                   # SwiftUI views (main, settings, logs, errors, about)
  ViewModels/              # Main and Settings view models
  Services/                # FFmpeg, FileManager, Settings, Logging, Performance
  Utilities/               # Helpers, extensions, optimizations
  Resources/               # Bundled assets (ffmpeg, licenses)
  Assets.xcassets          # App icons and colors
  Info.plist               # App configuration
  VideoSzhimakaApp.swift   # App entry and app delegate

VideoSzhimakaTests/
  ...                      # Unit, UI, integration, performance tests
```

---

## Testing
Run tests in Xcode (⌘U) or via CLI (see above). The test suite includes:
- Unit tests for services (FFmpeg, FileManager, Logging, Settings)
- View model tests (main/settings)
- UI and end‑to‑end tests (drag & drop, flows)
- Performance and crash/regression coverage

---

## Troubleshooting
- "Incompatible architecture" alert on launch: The app only supports Apple Silicon (arm64).
- FFmpeg not executing:
  - Confirm the binary exists at `VideoSzhimaka/Resources/bin/ffmpeg`
  - Ensure executable bit: `chmod +x VideoSzhimaka/Resources/bin/ffmpeg`
  - If macOS quarantines a locally replaced binary, you may need to remove quarantine attributes before development signing: `xattr -dr com.apple.quarantine VideoSzhimaka/Resources/bin/ffmpeg`
- Codesigning for distribution:
  - The project uses automatic signing for development. Configure your team/profile for notarized distribution.

---

## Localization
Current UI strings are in Russian. SwiftUI makes adding additional localizations straightforward.

---

## License
- App: © 2025 Видео-Сжимака. All rights reserved.
- FFmpeg: See `VideoSzhimaka/Resources/LICENSES/FFmpeg_LICENSE.txt` and comply with applicable license options for your build.

---

## Acknowledgements
- FFmpeg (`https://ffmpeg.org`)