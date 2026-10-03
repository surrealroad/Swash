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
- **Issue**: In styled ("Edit Text") mode, tables and images are collapsed into a single U+FFFC attachment character, so `NSTextView.selectedRange()` does not index into `document.text`. Applying a storage range to raw markdown edits the wrong span after an attachment.
- **Solution**: The `selectedRange` binding published by `SwashTextView` is **always in raw-markdown offsets**. Convert with `Coordinator.rawRange(forStorage:in:)` / `storageRange(forRaw:in:)` (backed by `AttachmentOffsetMap`). Never apply a raw range to the text storage, or a storage range to `document.text`, without mapping. Invalidate the cached map (`invalidateOffsetMap()`) whenever storage changes outside `textDidChange`.

## 10. Bubble-Menu Edits Must Go Through the Text View
- **Issue**: Assigning `document.text = …` from SwiftUI makes `updateNSView` reset `textView.string`, which bypasses `NSUndoManager`. The edit can't be undone, and selection and typing state are lost.
- **Solution**: Use `commitEdit(_:selection:actionName:)` in `ContentView`, which calls `SwashEditorController.apply`. That turns the rewrite into a minimal `shouldChangeText`/`replaceCharacters`/`didChangeText` edit on the live text view. Assign `document.text` directly only when no editor is attached.

## 11. `ObservableObject` Conformance Fails for Plain Helper Classes
- **Issue**: Declaring a property-less helper such as `final class SwashEditorController: ObservableObject` fails to build in this target (`does not conform to protocol 'ObservableObject'`).
- **Solution**: Don't make non-observable helpers `ObservableObject`. Hold the reference in `@State private var editor = SwashEditorController()`; `@State` keeps the same instance across view updates.

## 12. Code Detection Must Use `MarkdownParser.codeRanges(in:)`
- **Issue**: Ad-hoc checks (counting ``` lines, regexing backticks) miss `~~~` fences, indented code and multi-backtick spans. Calling them once per regex match made styling quadratic (27 s per keystroke at 2,200 lines).
- **Solution**: Compute `MarkdownParser.codeRanges(in:)` once per pass (one O(n) scan), then query it with `excludes(_:)`, `blockIntersects(_:)` or `spanContains(_:)` (binary search). `fencedCodeBlock(containing:in:)` locates the block around a selection.

## 13. `ObjectIdentifier` Keys Are Reused After Deallocation
- **Issue**: The Markdown parser keeps per-node side tables (block state, inline sources, text maps) keyed by `ObjectIdentifier`. When a node is discarded mid-parse (a paragraph absorbed into a setext heading, an emphasis delimiter run that was fully used), it can be deallocated and a new node allocated at the same address, which silently inherits the stale entry. Setext headings duplicated their text into the following paragraph until this was fixed.
- **Solution**: Side-table values must hold a strong reference to their node (`BlockState.node`, `(cell, source)`, `(node, map)`), so identifiers stay unique for the lifetime of the parse.

## 14. Command-Line Test Scripts Compile Explicit File Lists
- **Issue**: `scripts/run_spec_tests.sh`, `scripts/run_commonmark_spec.sh` and `Tests/EditorAudit/run_audit.sh` call `swiftc` with hand-picked source files. Moving a type into another file (for example `TableAlignment` and `AlertType` into `Swash/Markdown/MarkdownNode.swift`) breaks them, even though the Xcode build, which uses synchronised folders, still succeeds.
- **Solution**: After moving or adding source files, update the file lists in all three scripts. `Swash/Markdown/*.swift` is self-contained (Foundation only) and is included as a glob.

## 15. Xcode May Rewrite `project.pbxproj` When a New Source Folder Appears
- **Issue**: The first `xcodebuild` after adding `Swash/Markdown/` rewrote the synchronised-group membership exceptions (dropping `Swash.entitlements`), an unrelated project-file change.
- **Solution**: Check `git status` after builds and revert unintended `project.pbxproj` changes (`git checkout -- Swash.xcodeproj/project.pbxproj`). New files in synchronised folders need no project edits.

## 16. Test Key Handling Through `doCommand(by:)`, Not the Responder Methods
- **Issue**: Calling `textView.insertNewline(nil)`, `insertTab(nil)` or `deleteBackward(nil)` directly bypasses the `NSTextViewDelegate.textView(_:doCommandBy:)` hook, so Notion-style key handling (list continuation, indent, Backspace-unformat) appears not to work in tests.
- **Solution**: Send commands with `textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))`. This is the path real key presses take via `interpretKeyEvents`. For shortcuts, send a synthesised `NSEvent.keyEvent` to `performKeyEquivalent(with:)`.

## 17. Menus That Block Must Be Injectable for Headless Tests
- **Issue**: `NSMenu.popUp(positioning:at:in:)` runs a modal tracking loop, so the "/" block menu and the code-language menu can't be exercised in the headless harness.
- **Solution**: Presentation goes through replaceable static closures (`SwashTextView.Coordinator.blockMenuPresenter`, `languageMenuPresenter`). Tests substitute a closure that "chooses" an item. The insertion logic itself lives in `MarkdownEditingCommands` and is unit-tested.

## 18. Backticks in Shell-Quoted Commit Messages
- **Issue**: A commit message passed with `git commit -m "…"` that contains triple backticks is treated by zsh as command substitution, and the whole command line fails to parse ("unmatched").
- **Solution**: Write the message to a file and use `git commit -F <file>`, or avoid backticks in `-m` messages.

## 19. CI Builds With an Older SDK Than Local Xcode
- **Issue**: CI (`PR Build`, `Build & Release`) runs on `macos-26` with `latest-stable` Xcode, which can lag the local Xcode (a beta or newer release). AppKit signatures can differ between SDKs: `NSTextBlock.drawBackground(withFrame:in:characterRange:layoutManager:)` takes `NSView` on one SDK and `NSView?` on another, so an override that compiled locally broke the v1.5.0 release on `main`. Until v1.8.4, CI ran on `macos-14` (macOS 15.2 SDK), which was older than the 15.7 deployment target and logged deployment-target warnings on every build.
- **Solution**: Avoid overriding AppKit methods whose signatures have changed between SDKs, and prefer composition (here, `SwashLayoutManager` paints `IndentedTextBlock.fillColor`). The `PR Build` workflow builds every pull request on the release toolchain, so these failures show up before merging. Keep the CI runner's SDK at or above `MACOSX_DEPLOYMENT_TARGET`.

## 20. Incremental Restyling: Raw Text vs Partially Collapsed Storage
- **Issue**: Edit Text restyles only the changed blocks. Outside that region the text storage still holds collapsed table and image attachments, so storage offsets differ from AST (raw-Markdown) offsets by a constant shift, and `storage.string` is not the Markdown.
- **Solution**: `MarkdownEditorStyler` reads `document.source` and writes to the storage through `valid(_:)` (`raw location − storageShift`). Never read text from the storage or write raw ranges directly in the styler. Any code that replaces the storage or changes styling inputs (flavor, base URL, folder access, external text) must set `forceFullRestyle = true`. The interaction harness's `incremental-*` cases compare every incremental result with a full restyle; extend them when adding block types.

## 21. Bundled Web Resources Are Flattened, and Offscreen WebKit Snapshots Need Care
- **Issue**: Files under `Swash/Rendering/` (KaTeX, Mermaid, `swash-render.html`) are copied flat into the app's and Quick Look's `Resources`, because synchronised groups do not keep sub-folders. KaTeX's stylesheet expects a `fonts/` folder. KaTeX also loads its fonts lazily, so `document.fonts.ready` can resolve before the size fonts (∫, large delimiters) are requested, and the first snapshot is missing glyphs. `WKWebView.takeSnapshot` returns images at the backing scale of the `snapshotWidth` you give in points; passing pixel widths gives 4× images. SwiftUI stacks squeeze resizable images unless they are given `.fixedSize(horizontal: false, vertical: true)`.
- **Solution**: Refresh the vendor files only with `scripts/update_render_vendor.sh`, which rewrites the font URLs and keeps only woff2. The page loads every `FontFace` up front and awaits it before measuring. `RichContentRenderer` uses `pageZoom = 2` and `snapshotWidth` in points. Headless tests set `SWASH_RENDER_RESOURCES` to `Swash/Rendering`; without it, the renderer reports unavailable and every view falls back, so the other harnesses are unaffected. In a sandbox, WebKit needs outgoing connections (`network.client`), so the Quick Look extension sets `ENABLE_OUTGOING_NETWORK_CONNECTIONS`.

## 22. Scroll Positions Must Not Go Through SwiftUI State
- **Issue**: Split view synced the two panes through an `@State` scroll offset in `ContentView`. Every scroll tick re-evaluated `ContentView`, which re-parsed the whole preview, rebuilt its view tree and re-measured it with `fittingSize`, so scrolling stuttered on longer documents.
- **Solution**: `ScrollSync` (in `MarkdownPreviewView.swift`) scrolls the other pane's clip view directly and stores the offset in a plain class held in `@State`, so the mode-switch position is kept without invalidating views. Don't publish per-frame values (scroll offsets, unchanged selection rects) to SwiftUI state. `MarkdownPreviewView` also caches its parse by text and flavor.

## 23. Nested Horizontal Scroll Views Latch Vertical Gestures
- **Issue**: AppKit sends a whole trackpad scroll gesture, momentum included, to the scroll view under the pointer when it begins. In the preview, tables and code blocks sit in SwiftUI `ScrollView(.horizontal)` views (backed by `NSScrollView`), so a vertical swipe that began over one stalled there.
- **Solution**: `NestedScrollRouter` (in `MarkdownPreviewView.swift`) is a local `.scrollWheel` monitor. It decides at each gesture's `.began` (or per event for mouse wheels) and sends mostly-vertical gestures that start over a nested scroll view to the preview's `NSScrollView`. The decision lives in `shouldForward(...)` so the interaction harness can test it without a real event stream.

## 24. Release Version Comes From the Build Command, Not the Project
- **Issue**: `MARKETING_VERSION` is `1.0` in the project; `Build & Release` passes the changesets version (`MARKETING_VERSION=…`) on the `xcodebuild` command line. Extension `Info.plist` files that hard-coded `CFBundleShortVersionString` stayed at `1.0` and triggered "must match that of its containing parent app" warnings.
- **Solution**: Every target's `Info.plist` must use `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)` so the command-line override reaches the app and all extensions.

## 25. One Target, Two Platforms: Keep macOS-Only Code Behind `#if os(macOS)`
- **Issue**: The `Swash` app target builds for macOS and iOS (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx`, `SDKROOT = auto`). Every file in the synchronised `Swash/` folder compiles for both platforms, so any new AppKit use breaks the iOS build. Sparkle and the four extensions are macOS-only through `platformFilters = (macos, )` on their build files and target dependencies.
- **Solution**: Wrap AppKit-only files completely in `#if os(macOS)`, and put iOS-only UI in `Swash/iOS/` inside `#if os(iOS)`. Shared code uses `PlatformColor`, `PlatformFont`, `PlatformImage`, `Image(platformImage:)` and `PlatformPasteboard` from `PlatformTypes.swift`. Build both platforms before committing: `-destination 'generic/platform=macOS'` and `-destination 'generic/platform=iOS Simulator'`. The iOS app uses `Swash/Info-iOS.plist` (`INFOPLIST_FILE[sdk=iphone*]`), so document types and URL schemes must be added to both plists.

## 26. `XMLDocument` Is macOS-Only
- **Issue**: `HTMLToMarkdown` parses with Foundation's `XMLDocument` (`.documentTidyHTML`), which iOS does not have. The preview uses it for raw HTML blocks.
- **Solution**: On other platforms the converter uses `HTMLLiteDOM` through file-private type aliases with the same API. `scripts/run_commonmark_spec.sh` also builds the checks with `-D SWASH_HTML_LITE` so both parsers must pass the same HTML cases. Add new cases there when changing the converter.

## 27. Offscreen WebKit Rendering on iOS and iPadOS
- **Issue**: Without a viewport meta tag, iOS lays the render page out at 980 px and scales it to the view, so math and diagram snapshots came out cropped. On iPad, desktop-class browsing scaled them down to a fraction of their size. The first render also takes a few seconds while the WebContent process starts.
- **Solution**: `swash-render.html` declares `width=device-width, initial-scale=1` and `-webkit-text-size-adjust: 100%`. On iOS, `RichContentRenderer` sets `preferredContentMode = .mobile`. `UIImage.size` is read-only, so the snapshot is rebuilt with `scale = pixel width ÷ point width`. Check new rendering features on both an iPhone and an iPad simulator.

## 28. SwiftUI Text in Horizontal Scroll Views Under UIKit Hosting
- **Issue**: In the iOS preview (a `UIHostingController` sized by intrinsic content size inside a `UIScrollView`), a multi-line `Text` inside `ScrollView(.horizontal)` was squeezed to one line with an ellipsis.
- **Solution**: Give such text `.fixedSize()` (code blocks), or `.fixedSize(horizontal: false, vertical: true)` where it should wrap.
