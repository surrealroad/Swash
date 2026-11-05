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
- **Solution**: After moving or adding source files, update the file lists in all three scripts. The Markdown engine is not in this repo any more: each script sources `scripts/pixerate_markdown.sh`, which builds the `PixerateMarkdown` module once and passes it as `$PIXERATE_MARKDOWN` (#63).

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


## 41. Folder Windows: Watching Subfolders, Links and Headless Snapshots
- **Issue**: A `DispatchSource` file-system source on the folder only reports changes directly inside it, so files added or saved in subfolders went unnoticed. `NSTextView` opens a clicked `.link` with `NSWorkspace`, which can't open a relative URL such as `Other.md`. In headless snapshots (`cacheDisplay`), the `NavigationSplitView` sidebar's material draws as an empty white column even though the list has rows.
- **Solution**: `FolderWorkspace` watches the whole tree with an `FSEventStream` (it works in the sandbox for a folder whose security-scoped access is active) and rescans off the main thread with `FolderScanner` (`FolderIndex.swift`). Folder windows pass a `noteLinkHandler` and a `textRevealRequest` to the editor through the SwiftUI environment rather than through `ContentView`'s parameters (see #39). `SwashTextView.Coordinator` handles `textView(_:clickedOnLink:at:)` and marks `[[wiki]]` links as `swash-note:` links only while a handler is set. Because `SwashTextView.swift` now uses `NoteLinkResolver`, `Swash/FolderIndex.swift` is in every harness's file list (#14). In harnesses, check the sidebar through its `NSTableView` row count, not the snapshot.

## 42. Colour Runs Inside an `NSTextBlock` Make Layout Quadratic
- **Issue**: AppKit finds the extent of a paragraph's `NSTextBlock` (`rangeOfTextBlock:atIndex:`) by walking the text storage's attribute runs, and TextKit 1 does this once per laid-out line. Every syntax-colour run inside a code block therefore slows typing in that block: a 2,000-line JavaScript block went from ~0.7 s to ~2.2 s per keystroke with full colouring. Moving the colours to layout-manager temporary attributes was slower still (each call invalidates display).
- **Solution**: `CodeHighlighter` (`Swash/Markdown/`, Foundation only) tokenizes the whole block in one linear scan; `MarkdownCodeHighlighter.highlight(block:…)` (`Swash/CodeHighlightTheme.swift`, AppKit) colours a block in Edit Text only when it has at most `editorTokenLimit` tokens, and leaves larger blocks plain (the Preview, Quick Look and export still colour them). `Tests/EditorAudit/run_audit.sh perf` checks a 300-line block (coloured, under 100 ms) and a 2,000-line block (plain). `CodeHighlightTheme.swift` is in the explicit `swiftc` lists (GOTCHAS #14).

## 43. Typography Reaches the Editor and Preview as a Value, Not the Environment
- **Issue**: `PreviewScrollView` hosts the preview in its own `NSHostingView`, so SwiftUI environment values set by `ContentView` never reach the blocks. `MarkdownBlockView` is also `Equatable` (compared by source), so a settings change would not re-render unchanged blocks.
- **Solution**: `EditorTypography` (Settings › Appearance) is passed explicitly: `SwashTextView(typography:)`, `MarkdownPreviewView(typography:)` and `MarkdownRenderContext.typography`. It is part of the preview's `contentKey` and of `MarkdownBlockView ==`, and `updateNSView` treats a change like a flavor change (`forceFullRestyle`). The defaults (`EditorTypography()`) must reproduce the original styling exactly; `scaled(_:)` returns the size unchanged at 14 pt. Quick Look has no app group, so it can't read the app's defaults and always uses `EditorTypography()`.

## 44. Checking That Rendering Is Unchanged
- **Issue**: The tracked GFM snapshots were made on another machine, so a local run differs from them in every pixel even when nothing changed (see #8), and can't show whether a change altered the default rendering.
- **Solution**: Make a baseline on the same machine: commit work in progress, check out `origin/main`'s sources, run `scripts/run_spec_tests.sh` (and `run_audit.sh render`), copy `Tests/GFMSpec/snapshots` and `build/editor-audit/render-out` aside, restore your commit, run again and compare the PNGs pixel by pixel (decoded through `CGImage`; the files' bytes differ on every run).

## 45. Format Commands Come From a Generated Manifest
- **Issue**: The Format menu, keyboard shortcuts (`FormatCommand.command(for:)`), bubble-menu labels and tooltips, and the code-block language list are generated from `@pixerate/markdown-conformance`'s `manifest.json`, shared with the Pixerate web editor. Editing labels or shortcuts in `FormatCommands.swift` or `BubbleMenuView.swift` no longer has any effect, and the generated `FormatManifest.generated.swift` is in the PixerateMarkdown package, not here.
- **Solution**: Change the manifest in the Pixerate editor repo (`packages/markdown-conformance/manifest.json`), where `scripts/gen-swift-markdown.mjs` regenerates the Swift and a Swift release ships it; then bump Swash's pin (#63). The generator fails when the manifest names a surface or `enabledWhen` condition that `FormatSurface`/`FormatCondition` (in `FormatManifest.swift`) don't have, or a command id that `FormatCommand(manifestID:params:)` doesn't map; add the case (and, for a condition, its check in `MarkdownFormatting.satisfies(_:selection:)`) in the engine first. Letters in shortcuts match by character and digits/punctuation by ANSI key code (`FormatShortcut.keyCodes`), so shifted keys work on any layout. Swash-only commands (callouts, footnotes, table of contents) stay hand-written. The code-language menu lists the manifest's languages first, with the manifest's labels, then `CodeHighlighter`'s other languages (`CodeFormat.allCases`). The manifest type is `ManifestCodeLanguage`, so it doesn't clash with the highlighter's `CodeLanguage`. The conformance runner fails if a manifest language has no `CodeLanguage`.

## 46. The Conformance Runner Models the Text View's Fallbacks
- **Issue**: `MarkdownEditingCommands.newline`/`indent`/`backspace` return nil when the editor should fall back to the default key behaviour, so comparing their raw result with the shared corpus reports false failures (and hides real ones: Tab on an unnestable list item used to insert a tab character).
- **Solution**: `Tests/MarkdownConformance/ConformanceRunner.swift` applies the `NSTextView` default when an `edit.*` command returns nil (Return inserts `\n`, Backspace deletes, Tab inserts `\t`, Shift-Tab does nothing) and runs Backspace with `markersHidden: true`, as in Edit Text. Intended differences from the corpus go in the runner's `localSkips` with a reason until a `variants.swash` entry lands upstream; the runner warns about local skips that no longer match a case. `FormatCommand`, `FormatCommandEdits` and the manifest types are in `PixerateMarkdown`, and the corpus comes from the same editor checkout, so it always matches the engine's manifest version (#63).

## 47. One Target, Two Platforms: Keep macOS-Only Code Behind `#if os(macOS)`
- **Issue**: The `Swash` app target builds for macOS and iOS (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx`, `SDKROOT = auto`). Every file in the synchronised `Swash/` folder compiles for both platforms, so any new AppKit use breaks the iOS build. Sparkle and the four extensions are macOS-only through `platformFilters = (macos, )` on their build files and target dependencies.
- **Solution**: Wrap AppKit-only files completely in `#if os(macOS)`, and put iOS-only UI in `Swash/iOS/` inside `#if os(iOS)`. Shared code uses `PlatformColor`, `PlatformFont`, `PlatformImage`, `Image(platformImage:)` and `PlatformPasteboard` from `PlatformTypes.swift`. Build both platforms before committing: `-destination 'generic/platform=macOS'` and `-destination 'generic/platform=iOS Simulator'`. The iOS app uses `Swash/Info-iOS.plist` (`INFOPLIST_FILE[sdk=iphone*]`), so document types and URL schemes must be added to both plists.

## 48. `XMLDocument` Is macOS-Only
- **Issue**: `HTMLToMarkdown` parses with Foundation's `XMLDocument` (`.documentTidyHTML`), which iOS does not have. The preview uses it for raw HTML blocks.
- **Solution**: On other platforms the converter uses `HTMLLiteDOM` through file-private type aliases with the same API. Both now live in the `PixerateMarkdown` package (#63), whose `PIXERATE_HTML_LITE` flag runs the lite parser on macOS for tests. Add HTML cases there when changing the converter.

## 49. Offscreen WebKit Rendering on iOS and iPadOS
- **Issue**: Without a viewport meta tag, iOS lays the render page out at 980 px and scales it to the view, so math and diagram snapshots came out cropped. On iPad, desktop-class browsing scaled them down to a fraction of their size. The first render also takes a few seconds while the WebContent process starts.
- **Solution**: `swash-render.html` declares `width=device-width, initial-scale=1` and `-webkit-text-size-adjust: 100%`. On iOS, `RichContentRenderer` sets `preferredContentMode = .mobile`. `UIImage.size` is read-only, so the snapshot is rebuilt with `scale = pixel width ÷ point width`. Check new rendering features on both an iPhone and an iPad simulator.

## 50. SwiftUI Text in Horizontal Scroll Views Under UIKit Hosting
- **Issue**: In the iOS preview (a `UIHostingController` sized by intrinsic content size inside a `UIScrollView`), a multi-line `Text` inside `ScrollView(.horizontal)` was squeezed to one line with an ellipsis.
- **Solution**: Give such text `.fixedSize()` (code blocks), or `.fixedSize(horizontal: false, vertical: true)` where it should wrap.

## 51. Don't Make a UITextView Subclass Its Own Gesture Delegate
- **Issue**: `StyledUITextView` implemented `gestureRecognizer(_:shouldReceive:)` to limit its task-checkbox tap to checkboxes. A scroll view is already the delegate of its own pan and text-interaction recognizers, so the override filtered those too. The editor stopped scrolling, with no error and no `scrollViewDidScroll` calls.
- **Solution**: Give extra recognizers on a text or scroll view a separate delegate object (`TaskTapFilter`). Never implement `UIGestureRecognizerDelegate` methods on the scroll view subclass itself.

## 52. UITextView in UIViewRepresentable Must Fill the Proposed Size
- **Issue**: SwiftUI can size a representable `UITextView` to its fitting size, which is the whole text height, so the view grows instead of scrolling.
- **Solution**: Both iOS editors implement `sizeThatFits(_:uiView:context:)` and return the proposed width and height.

## 53. Edit Text Blocks on iOS: Decorations Instead of NSTextBlock
- **Issue**: iOS has no `NSTextBlock`, which the styler uses on macOS for quotes, alerts, code blocks and rules.
- **Solution**: On iOS, `MarkdownEditorStyler.pushBox`/`pushRule` add a `BlockDecoration` (outermost first) to the context instead. `setParagraphStyle(_ context:…)` sets the paragraph indents for the box's border and padding and writes `.blockDecorations` over the paragraphs. `padBoxes()` turns top and bottom padding into paragraph spacing, and `StyledLayoutManager` paints each box over its paragraphs' line fragments. Always set paragraph styles through `setParagraphStyle(context:…)`. When adjusting a paragraph style later, adjust the indents (`tailIndent -= …`) rather than replacing them, or the box insets are lost on iOS. macOS keeps its `NSTextBlock` path unchanged; check it with `Tests/EditorAudit/run_audit.sh`.

## 54. Default MainActor Isolation and Callbacks on Background Queues
- **Issue**: Every target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Closures in a type that isn't marked otherwise are treated as main-actor code, and Swift traps (`EXC_BREAKPOINT`) when a framework calls them off the main thread. The thumbnail extension crashed this way on macOS: Quick Look runs `QLThumbnailReply`'s drawing block on a background queue.
- **Solution**: Mark extension principal classes whose callbacks arrive on background queues `nonisolated` (as `ThumbnailProvider` is), or mark the specific closures `@Sendable`/`nonisolated`. Check new extension points or framework callbacks for the queue they run on.

## 55. ShareLink in a Collapsed Toolbar Menu Crashes on iPhone
- **Issue**: A `ShareLink` in a `.secondaryAction` toolbar item, which collapses into the overflow menu on iPhone, presents `UIActivityViewController` as a popover with no source view. UIKit throws an uncaught `NSGenericException`.
- **Solution**: Use a `Button` that presents `UIActivityViewController` itself with `popoverPresentationController.sourceView`/`sourceRect` set (`IOSContentView.presentShareSheet()`).

## 56. Opening Documents From Code on iOS
- **Issue**: SwiftUI's `openDocument` and `newDocument` environment actions are macOS-only. On iOS, `onOpenURL` on a document view doesn't fire while the document browser is showing, and the browser is a presented card on the launch screen but absent from the hierarchy once a document is open.
- **Solution**: `DocumentOpener` receives `swash://` URLs in a `UIWindowSceneDelegate` (installed through `@UIApplicationDelegateAdaptor` and `configurationForConnecting`). It finds the browser through `UIDocumentViewController.launchOptions.browserViewController`, which works whether or not a document is open. It then calls the browser delegate's `documentBrowser(_:didPickDocumentsAt:)` with the file. Pass files in the app's own Documents folder directly: `revealDocument(at:importIfNeeded: true)` copies them ("Name 2.md").

## 57. iOS Prefers Its Own Quick Look Viewer for Markdown
- **Issue**: iOS has a built-in Markdown previewer and thumbnailer. In Files, they take precedence over a third-party Quick Look preview or thumbnail extension for `net.daringfireball.markdown`, so Swash's extensions registered but never ran.
- **Solution**: The Quick Look and thumbnail extensions are filtered to macOS (`platformFilters = (macos, )`). Only the share extension and widget are built and embedded for iOS.

## 58. Confluence and Jira Copy Images Without an `<img>` Tag
- **Issue**: Atlassian's editor puts each image on the pasteboard as an empty `<div data-node-type="media">` with `data-file-name`/`data-alt` and `data-context-id` (the page ID). There is no `src` and no image data, so a converter that only reads `<img>` drops the images.
- **Solution**: `HTMLToMarkdown.convert(_:sourceURL:)` (`Swash/PixerateMarkdownExtensions.swift`) rewrites media nodes as `<img>` before the package converts the HTML. Their source is `https://<site>[/wiki]/download/attachments/<pageID>/<file>`. It takes the site from the `org.chromium.source-url` pasteboard type, which Chromium browsers write. Safari does not write this type, so without it the image keeps only its file name. The attachment needs a signed-in browser, so Swash shows a placeholder for it.

## 59. Don't Re-Identify a View That Declares a Customizable Toolbar
- **Issue**: The folder window first gave `ContentView` an `.id(file)` so each file got fresh editor state. Every switch rebuilt `ContentView`'s `.toolbar(id: "mainToolbar")`, and AppKit threw `NSInternalInconsistencyException` (`index>=0 && index<[_currentItems count]` in `-[NSToolbar _removeItemAtIndex:]`) while SwiftUI removed the old items. A headless `NSHostingView` harness doesn't crash, because it has no window toolbar.
- **Solution**: Keep the view that owns the toolbar stable and reset only the part below it. `ContentView` takes a `documentID` and applies `.id(documentID)` to the editor area, clears its selection state in `onChange(of: documentID)`, and keeps one `ScrollSync` per file (`ScrollSyncStore`). Reproduce toolbar issues in the real app, for example by launching the Debug build binary under `lldb`.

## 60. MacAppKitExtras Is a Separate Module
- **Issue**: `FolderAccessManager`, `DefaultAppManager`, `ScrollSync` and `NestedScrollRouter` live in the local package `Packages/MacAppKitExtras`, not the app target. The swiftc-based runners that compile app sources (`run_spec_tests.sh`, `run_rich_render_tests.sh`, `run_export_tests.sh`, `Tests/EditorAudit/run_audit.sh`) compile app sources directly, so `import MacAppKitExtras` fails unless the module is built first. They also compile without the app's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so calling the package's `@MainActor` scroll helpers from an unannotated callback fails there (`call to main actor-isolated instance method ... in a synchronous nonisolated context`) even though the app builds.
- **Solution**: Runners get `EXTRAS="$(scripts/build_mac_appkit_extras.sh)"` and pass `$EXTRAS` to `swiftc`. Annotate app code that calls the package's `@MainActor` APIs explicitly with `@MainActor`. Swash's configuration (the bookmarks defaults key, alert and panel text) is in `Swash/FolderAccessManager.swift` and `Swash/DefaultAppManager.swift` as `static let shared` extensions; keep the `swash_security_scoped_folder_bookmarks` key, or users lose folders they already granted. Run the package's own tests with `swift test --package-path Packages/MacAppKitExtras`.

## 61. Unnamed Dynamic Colours Aren't Equal
- **Issue**: `PlatformColor.appearanceAware(light:dark:)` (an unnamed `NSColor(name: nil)` / `UIColor { traits in … }`) returns a new colour on every call, and two such colours never compare equal. Code that checks `textView.backgroundColor != color` before assigning, or a test that compares against `EditorTheme.paper.background`, then sees a change every time.
- **Solution**: Create each dynamic colour once (a `static let`) and hand out that instance, as `EditorTheme.paperBackground` and `CodeHighlightTheme`'s table do.

## 62. The Outline Is a Split View Column, and SwiftUI's Sidebar Button Clashes Across Windows
- **Issue**: The heading outline was an `HStack` column beside the editor. The unified toolbar didn't know about it, so the window title and toolbar ran across the sidebar's edge. It couldn't simply become a `NavigationSplitView`, because `ContentView` is also the detail of the folder window's split view and split views don't nest. A 3-column split doesn't work either: it can't hide only the middle column (files + editor with the outline hidden). Once document windows had a split view, opening a second document crashed: `NSToolbar … already contains an item with the identifier com.apple.SwiftUI.navigationSplitView.toggleSidebar`. Every window's toolbar is `"mainToolbar"`, AppKit syncs toolbars that share an identifier, and each window added SwiftUI's sidebar button. The bubble harness (`run_audit.sh bubble`), which opens a window per case, crashed the same way.
- **Solution**: `ContentView` wraps its editor in a 2-column `NavigationSplitView` only when it has no `hostedOutline`. It removes SwiftUI's button with `.toolbar(removing: .sidebarToggle)` and keeps its own `"outline"` toggle item. Folder windows pass a `DocumentOutlineState` as `hostedOutline` and show it under an Outline tab in the file sidebar. View › Show Outline acts through the `outlineVisibility` focused value, so each window type decides what it means.

## 63. The Markdown Engine Is the PixerateMarkdown Package
- **Issue**: The parser, renderer, HTML → Markdown converter, code highlighter and the formatting and editing commands used to live in `Swash/Markdown/` and could be changed with the app. They now come from the `PixerateMarkdown` product of the Pixerate editor repo (Swash #50, Pixerate/editor#546), so an engine change made here has nowhere to go, and an engine API that isn't `public` can't be used.
- **Solution**: Change the engine in the editor repo (`packages/swift/Sources/PixerateMarkdown`, with tests in `packages/swift/Tests/PixerateMarkdownTests`), release it (a `v<version>` tag), then bump Swash: Xcode › Package Dependencies, or the `minimumVersion` in `project.pbxproj` and `Package.resolved`. The dependency is `upToNextMinor`, because a 0.x minor can break. `Package.resolved` is committed (`git add -f`, since `project.xcworkspace` is ignored): `scripts/pixerate_markdown.sh` reads the pinned revision from it and fetches the engine, its checks and the conformance corpus into `build/pixerate-editor` (sparse), then builds the module with `swiftc` for every test script. To try engine changes before a release, point the scripts at a local checkout with `PIXERATE_EDITOR_DIR=../editor`, and Xcode at it by dragging the checkout into the project (a local package overrides the remote one). The Quick Look extension compiles the app's sources, so it depends on the product too; Share, Thumbnail and Widget don't use the engine. Sources that use engine types `import PixerateMarkdown`.
