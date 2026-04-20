# Mettle

A native macOS confidence monitor for a wired iPhone. Displays your iPhone's
live screen in a resizable, aspect-locked window while you film with a camera
app on the phone. Purpose-built ergonomics: horizontal mirror for selfie-style
framing, always-on-top, chrome-hiding, plus an optional teleprompter window.

## Requirements

- macOS 13 Ventura or later
- An iPhone connected via cable (USB-C or Lightning)
- "Trust This Computer" tapped on the iPhone
- Camera permission granted on first launch (iOS devices appear under the
  camera privacy umbrella)

## Features

- Auto-discovery of wired iPhones with hot-plug support
- Live preview with ~100–200ms latency (inherent to the capture pipeline)
- Window auto-sizes to the iPhone's feed aspect ratio and locks resize to it
- Smooth animated re-fit when you rotate the phone
- Horizontal mirror (⌘M)
- Always on top (⌘T)
- Hide window chrome (⌘⇧F) — Esc bails out
- Teleprompter window (⌘⌥T) with adjustable font size, scroll speed,
  play/pause (Space), rewind, and optional horizontal mirror
- Auto-updates via [Sparkle](https://sparkle-project.org/)

## Build

Project file is generated from `project.yml` with [xcodegen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate
open Mettle.xcodeproj
```

Or from the command line:

```bash
xcodegen generate
xcodebuild -project Mettle.xcodeproj -scheme Mettle -configuration Release build
```

## Notes

- The iOS device's own camera session may be interrupted by macOS when screen
  capture starts. Apps running on the iPhone should observe
  `AVCaptureSession.wasInterruptedNotification` and restart their session
  when the interruption ends.
- For distribution, the app must be Developer ID signed and notarized for
  Sparkle's EdDSA signature verification to work.
