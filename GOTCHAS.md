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

## 5. Changeset Status Verification on `main`
- **Issue**: Running `npx changeset status --since=origin/main` when working directly on `main` before committing fails with `Error: Failed to find where HEAD diverged from "origin/main"` because HEAD has not diverged from origin/main yet.
- **Solution**: Manually verify that `.changeset/<unique-name>.md` conforms to the valid frontmatter format (`--- \n "swash": <type> \n ---`), or check status after creating local commits on a branch or relative to `HEAD~1`.

## 6. App Sandbox vs. Sibling Document Assets (Images) & Security-Scoped Bookmarks
- **Issue**: When `ENABLE_APP_SANDBOX = YES` is set on the main app target, macOS sandbox Powerbox only grants security access to the exact user-selected Markdown file, not its containing directory. Any relative asset links (such as `![Screenshot](Screenshot.png)`) fail to load at runtime because file reading (`isReadableFile`, `NSImage(contentsOfFile:)`) is denied by sandbox kernel rules, causing the editor to render placeholder badges instead of images.
- **Solution**: Re-enable App Sandbox on the main `Swash` target (`ENABLE_APP_SANDBOX = YES`) with user-selected file read/write and app-scoped bookmark entitlements (`com.apple.security.files.user-selected.read-write`, `com.apple.security.files.bookmarks.app-scope`). When unreadable relative image assets are detected in a document, display a prominent access banner with a "Grant Access…" button (and provide `File -> Grant Folder Access…` menu command). Present an `NSOpenPanel` targeting the document's directory so the user can grant folder access at runtime. Save the resulting security-scoped URL bookmark to `UserDefaults` and resolve/activate it via `startAccessingSecurityScopedResource()` on subsequent launches for seamless persistence across app restarts.



## 7. Driving the UI for Automated Testing (Bubble Menu, Editor Interactions)
- **Issue**: `osascript`/System Events UI scripting fails with `osascript is not allowed assistive access (-1728)` from agent shells. Walking the SwiftUI accessibility tree in-process (`NSHostingView.accessibilityChildren()`) also returns only an empty `AXGroup`, because SwiftUI populates its AX tree only when an assistive client is attached.
- **Solution**: Host the real views in-process (see `Tests/EditorAudit/`). Send `NSTextView` commands directly (`insertNewline`, `insertTab`, `deleteBackward`, `moveRight`, `undoManager.undo()`). For the bubble menu, `run_audit.sh` injects a `TestHooks` capture into a *copy* of `BubbleMenuView.swift` so the harness can invoke the exact closures the buttons call.

## 8. Spec Runner Overwrites Tracked Snapshots
- **Issue**: `./scripts/run_spec_tests.sh` writes PNGs directly into the git-tracked `Tests/GFMSpec/snapshots/`, so every run dirties ~100 files with byte-level differences.
- **Solution**: After a local run, restore with `git checkout -- Tests/GFMSpec/snapshots` unless the snapshots were intentionally regenerated.

## 9. Editor Text Storage Offsets ≠ Raw Markdown Offsets
- **Issue**: In styled ("Edit Text") mode, tables and images are collapsed into a single U+FFFC attachment character, so `NSTextView.selectedRange()` does not index into `document.text`. Any code applying a selection range to raw markdown edits the wrong span after an attachment (see `docs/WYSIWYG_AUDIT.md` §3).
- **Solution**: Map ranges through the attachments (storage ↔ raw) before applying edits to `document.text`, or apply edits to the text storage itself.
