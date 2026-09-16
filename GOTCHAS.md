# Gotchas & Known Pitfalls

## 1. Sandbox Permissions for `xcodebuild` and `git`
- **Issue**: Standard sandboxed execution can block read/write operations to Developer directory caches (`~/Library/Developer/Xcode/DerivedData`, `/var/folders/.../C/clang/ModuleCache`) and user git configuration (`~/.gitconfig`), resulting in `Operation not permitted (error code 1 / 257)`.
- **Solution**: Execute build commands (`xcodebuild`) and git operations with appropriate permissions (`BypassSandbox: true` where needed) to ensure access to Xcode toolchains, standard SDKs, and git configs.

## 2. Headless AppKit & SwiftUI Snapshot Rendering
- **Issue**: Calling `cacheDisplay(in:to:)` on an `NSView` or `NSHostingView` before layout completes or without setting a frame size can produce empty 0x0 images.
- **Solution**: Set an explicit frame on `NSHostingView` (or compute `fittingSize`), call `layoutSubtreeIfNeeded()` and `displayIfNeeded()`, and create an `NSBitmapImageRep` matching the view bounds.

## 3. Changeset Requirements
- **Issue**: Missing changeset files cause CI failures on pull requests and commits.
- **Solution**: Every PR and task must include a changeset file in `.changeset/<unique-name>.md` created via `npx changeset` or by writing the markdown file directly.

## 4. Main RunLoop in Headless CLI Test Runners
- **Issue**: Async main queue dispatches (such as `DispatchQueue.main.async` inside `updateNSView` or coordinator callbacks) do not execute in headless command-line tools without an active event loop.
- **Solution**: Pump `RunLoop.main.run(until: Date().addingTimeInterval(...))` before capturing snapshots or evaluating asynchronously updated view states.
