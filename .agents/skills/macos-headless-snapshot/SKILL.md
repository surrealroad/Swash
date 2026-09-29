---
name: macos-headless-snapshot
description: >-
  Capture UI snapshots and generate README screenshots for Swash using AppKit and SwiftUI.
  Use when updating UI documentation, capturing window screenshots, or working on headless view rendering.
---

# macOS Headless Snapshot & Screenshot Generation

This skill covers generating UI screenshots and managing headless AppKit/SwiftUI snapshot tests.

## 1. Generating the README Screenshot

To capture a high-resolution window screenshot of Swash with the sample preview:

```bash
./scripts/generate_screenshot.sh
```

### How it works:
1. Builds a release binary of `Swash.app` if not present.
2. Launches `Swash.app` with `scripts/sample_preview.md` using `--select-sample`.
3. Runs `scripts/get_window_id.swift` to locate the CGWindowID of the running app window.
4. Uses macOS `screencapture -l <WINDOW_ID>` to grab the window without background interference.
5. Saves to `Screenshot.png` in the repository root.

## 2. Headless AppKit & SwiftUI Snapshot Rendering Gotchas

When rendering AppKit or SwiftUI views in headless test runners (such as CLI tools or unit tests):

- **Explicit Frame Bounds**: Calling `cacheDisplay(in:to:)` on an `NSView` or `NSHostingView` before layout completes or without setting a frame size produces empty `0x0` images. Always set an explicit frame or compute `fittingSize`, then call `layoutSubtreeIfNeeded()` and `displayIfNeeded()`.
- **RunLoop Pumping**: Dispatches to the main queue (e.g. `DispatchQueue.main.async` in coordinators, text layout managers, or view updates) will not execute in headless command-line tools without an active event loop. Pump the loop before capturing view snapshots:
  ```swift
  RunLoop.main.run(until: Date().addingTimeInterval(0.1))
  ```
