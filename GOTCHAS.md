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

## 25. "Metadata extraction skipped" Warnings From App Extensions
- **Issue**: Xcode runs `ExtractAppIntentsMetadata` for every Swift target. Extensions that don't link AppIntents (QuickLook, Share, Thumbnail) log `appintentsmetadataprocessor warning: Metadata extraction skipped, no AppIntents.framework dependency found` on every build, including CI. `LM_FILTER_WARNINGS = YES` (`--quiet-warnings`) does **not** silence it.
- **Solution**: Set `LM_SKIP_METADATA_EXTRACTION = YES` on those extension targets (Debug and Release) so the step doesn't run. Leave it unset on `Swash` and `SwashWidgetExtension`, which do use App Intents. A new extension that adopts App Intents must remove the setting, or Shortcuts won't see its intents.

## 26. Images Go Through `ImageCache`
- **Issue**: Loading and scaling images directly (`NSImage(contentsOfFile:)` plus `scaleImageForEditor`) in a styling pass or a SwiftUI `body` re-reads the file on every keystroke near the image and on every preview render.
- **Solution**: Resolve images with `MarkdownParser.resolveImageFile`, which checks candidate paths cheaply and loads through `ImageCache.shared`; scale with `ImageCache.shared.editorImage(_:path:maxWidth:)`. Entries are validated by modification date and size. Folder access is started once per folder per session by `FolderAccessManager.ensureAccess`; don't call `startAccessingSecurityScopedResource()` elsewhere.

## 27. Test Harnesses Compile `SwashTextView.swift` for macOS 14
- **Issue**: `run_audit.sh` (render, interact, perf) and `run_spec_tests.sh` build with `-target arm64-apple-macos14.0`, while the app targets macOS 15. macOS 15-only APIs such as the Writing Tools delegate methods (`textViewWritingToolsWillBegin`, `writingToolsIgnoredRangesInEnclosingRange`) break those builds even though Xcode succeeds.
- **Solution**: Mark macOS 15-only members of the shared editor files `@available(macOS 15.0, *)` (delegate methods can be declared this way), or guard calls with `if #available`.

## 28. The Bubble Harness Compiles `ContentView`'s Dependencies Explicitly
- **Issue**: `run_audit.sh bubble` compiles `ContentView.swift` with a hand-written file list. Any new type that `ContentView` uses (outline sidebar, document commands, quick note, conflict banner, document opening) has to be in that list, or the harness fails with "cannot find type".
- **Solution**: When `ContentView` starts using a new file, add it to the `bubble` `swiftc` line. Keep app-only machinery (Carbon hot keys, `SMAppService`, menu bar) in files that still compile outside the app.

## 29. Writing Tools Edits the Text Storage In Place
- **Issue**: Apple Intelligence Writing Tools rewrites `NSTextView` storage directly, with its own animation attributes. Restyling during a session (which replaces attributes, collapses tables and images into attachments, and pushes `document.text` and autosaves) fights it and can corrupt the rewrite.
- **Solution**: `Coordinator.isWritingToolsActive` is set between `textViewWritingToolsWillBegin`/`DidEnd`. While it is set, `highlightMarkdown` and `textDidChange` do nothing; after the session one full restyle and document update runs. Code, math, HTML, front matter and attachments are reported as ignored ranges, in storage coordinates.

## 30. Untitled Documents With Initial Text
- **Issue**: `DocumentGroup` creates new documents from `SwashDocument()`, so there's no direct way to open an untitled document that already has text (quick notes, imports). Writing a temporary file and opening it makes Save write into the temporary folder.
- **Solution**: `NewDocumentSeed.createDocument(with:)` queues the text and calls `NSDocumentController.newDocument(_:)`. `ContentView.onAppear` takes the next seed when its document is untitled and empty.

## 31. macOS App Icon HIG Grid Dimensions & Drop Shadow
- **Issue**: Exporting app icons with generic or iOS squircle padding (e.g. 75% scale or 768px body with 128px margins on a 1024x1024 canvas) makes the icon appear ~6.3% smaller than surrounding apps in the macOS Dock and Launchpad. Additionally, macOS does not automatically synthesize dock drop shadows for custom icons, so icons without Apple's subtle downward drop shadow appear ungrounded and floating.
- **Solution**: Follow Apple's macOS Human Interface Guidelines (HIG) App Icon grid specifications: the squircle body must occupy 824 × 824 px centered on a 1024 × 1024 canvas (100 px margins top/bottom/sides, ~80.5% fill). Include the standard Apple HIG downward drop shadow (offset `dy = +10`, Gaussian blur `radius = 16`, opacity `~28%`) in the asset artwork so the icon sits seamlessly on the Dock shelf alongside native system apps.

## 32. SwiftUI Overlays Don't Change the Text View's Cursor
- **Issue**: The bubble menu is a SwiftUI `.overlay` drawn over the `NSTextView`'s scroll view, not an `NSView` with its own cursor rects. The text view keeps setting the I-beam, including over its 20 pt inset margins.
- **Solution**: `SwashNSTextView.overrideCursor(at:)` returns the arrow over the margins and over `bubbleMenuFrame` (in overlay coordinates, kept up to date through `SwashEditorController.bubbleMenuFrame`), and the pointing hand over checkboxes and footnote links. `mouseMoved` and `cursorUpdate` apply it. `BubbleMenuView` also sets the arrow with `onContinuousHover`.

## 33. Table Attachments Are Sized From Their SwiftUI Content
- **Issue**: `TableAttachmentCell` used to guess its height (36 pt per row). The hosting view then held content of a different height, so any state change (a cell entering edit mode, the header chevron appearing) moved the whole table. The edit cell (`NSTextView`) was also taller than the display `Text`, and had a different weight and alignment.
- **Solution**: The cell measures `hostingView.fittingSize` (cached per table data and width). Display and edit cells share `CellTextField.lineHeight`, and the edit cell copies the header weight and the column alignment. The column menu is always laid out and only hidden. Cell parses are cached (`InlineMarkdownText`), and `.cellSelectionDidChange` is posted only when the selection actually changes.

## 34. Custom Attributed-String Values Must Be `Hashable`
- **Issue**: Storing an `Equatable`-only Swift struct as an attribute value logs "Obj-C `-hash` invoked on a Swift value … that is Equatable but not Hashable", and attribute run coalescing gets slow.
- **Solution**: Make attribute value types (`FootnoteLink`, …) `Hashable`.

## 35. An `<img>` Alone on a Line Is an HTML Block
- **Issue**: CommonMark parses a line holding just `<img …>` as an HTML block (type 7), not inline HTML. The image menu writes exactly that when an image gets a width, and the editor used to show the tag as source.
- **Solution**: `MarkdownEditorStyler` turns an HTML block holding a single `<img>` into an image attachment, and `MarkdownFormatting.image(exactly:)` accepts both `htmlInline` and `htmlBlock` images.

## 36. `NSTextBlock` Background Expands Into `paragraphSpacingBefore`
- **Issue**: Setting `paragraphSpacingBefore` on an `NSMutableParagraphStyle` that contains an `NSTextBlock` causes AppKit's text system to include the leading paragraph spacing inside the text block's bounding rectangle. Consequently, the text block's `backgroundColor` fills the entire spacing area above the line, turning a 1-2 pt horizontal divider line (`thematicBreak`) into an unexpectedly thick (12+ pt) block.
- **Solution**: Keep `paragraphSpacingBefore = 0` (and `paragraphSpacing = 0`) on paragraph styles containing `NSTextBlock` dividers, and size the line via font height (`font = NSFont.systemFont(ofSize: 2)`) and line height metrics.

## 37. Edit Text Display String Isn't the Markdown
- **Issue**: Tables, images and (since 1.14.0) Mermaid blocks are replaced in the editor's text storage by an attachment character (`U+FFFC`), so `NSTextView.string` no longer equals the document. Tests that compared `tv.string` with the source started failing in `scripts/run_rich_render_tests.sh` once Mermaid became an attachment, and the PR build stayed red.
- **Solution**: Compare the Markdown written back through the editor's text binding (`box.text` in the harnesses), and find diagrams as `ImageTextAttachment`s (alt `"Mermaid Diagram"`) rather than `.richPreview` overlays.

## 38. `NSPrintOperation` Calls Back on Its Own Thread
- **Issue**: `DocumentExporter` prints a `WKWebView` with `runModal(for:delegate:didRun:contextInfo:)` (`run()` gives blank pages). With no panel shown, AppKit calls the `didRun` selector on the print operation's thread, not the main thread. Under default main-actor isolation, touching the window there crashed with `EXC_BREAKPOINT` in `WKWindowVisibilityObserver`.
- **Solution**: Declare the callback `@objc nonisolated` and hop to the main queue before touching the web view, window or continuation. The web view lives in an offscreen borderless window while it prints, and the print operation's view needs a non-zero frame.

## 39. `ContentView.body` Is Near the Type-Checker's Limit
- **Issue**: Adding a few more `.focusedSceneValue` and `.onReceive` modifiers to `ContentView.body` failed the build with "the compiler is unable to type-check this expression in reasonable time".
- **Solution**: Group new modifiers in a small `ViewModifier` (such as `ExportAndWritingCommandsModifier`) and apply it with `.modifier(...)`, rather than extending the chain.

## 40. Sandboxed Apps Can't Read Files Passed on the Command Line
- **Issue**: Launching the app binary directly with a document path (`Swash.app/Contents/MacOS/Swash file.md`) shows "Swash doesn't have permission to read it": only Launch Services grants the sandbox access. `pkill -x Swash` in scripts also quits the user's own copy of Swash.
- **Solution**: Open documents with `open -n -a <app> <file> --args …`, find the new process with `pgrep -n -f <app path>`, and quit only that PID (`scripts/generate_readme_screenshots.sh`). `-NSRequiresAquaSystemAppearance YES` and `-AppleInterfaceStyle Dark` force Light or Dark Mode for one launch.

