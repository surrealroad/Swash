# Swash for iPhone and iPad: Plan

Swash is a native macOS app. This plan makes it a universal app that runs natively on macOS, iPadOS and iOS. Every platform gets the same features, presented with that platform's own interaction patterns.

Status: **in progress** on the `feat/universal-ios` branch. The phase checklists below track progress.

## Decisions

| Question | Decision | Why |
|---|---|---|
| Approach | AppKit on macOS, UIKit and SwiftUI on iOS and iPadOS. No Mac Catalyst. | The Mac app is the reference experience and must not get worse. |
| Targets | One `Swash` app target that builds for both macOS and iOS. macOS-only frameworks and extensions are excluded from iOS builds with platform filters. | One scheme and one version number. Shared code is compiled once per platform. |
| Code sharing | Shared sources stay in `Swash/` (synchronized folder). Platform-specific code is either a whole file wrapped in `#if os(macOS)` / `#if os(iOS)`, or lives under `Swash/iOS/`. | Avoids reworking the hand-written file lists in the test scripts for now (GOTCHAS #14). Moving shared code into a `SwashCore` Swift package is deferred. See GOTCHAS #25. |
| Platform types | `PlatformTypes.swift` defines `PlatformColor`, `PlatformFont` and `PlatformImage`, plus helpers that hide UIKit/AppKit differences (semantic colours, `Image(platformImage:)`, pasteboard). | Most of the AppKit dependency in shared code is just type names. |
| Minimum OS | iOS / iPadOS 26.0. macOS stays at 15.7. | Gets iPadOS menu-bar and windowing behaviour, and keeps `#available` checks to a minimum. |
| Editor engine on iOS | `UITextView` on TextKit 1 (`NSLayoutManager`), mirroring the AppKit editor. | The styler and the raw/storage offset mapping (GOTCHAS #9, #20) assume TextKit 1, which iOS also supports. A TextKit 2 rewrite is not needed. |
| Distribution | iOS builds are development and simulator builds for now. App Store / TestFlight comes in phase 6. The Mac app keeps its GitHub + Sparkle releases. | No App Store Connect signing is set up in CI yet. |

## How much of the code is AppKit-specific

| Area | Files | Portability |
|---|---|---|
| Markdown core | `Swash/Markdown/*` | Foundation only, except `HTMLToMarkdown`'s use of `XMLDocument`. iOS uses `HTMLLiteDOM` instead (GOTCHAS #26). |
| Document model, flavour, settings | `SwashDocument`, `MarkdownFlavor`, `SettingsView` | SwiftUI. Mostly portable. |
| Preview ("Formatted") | `MarkdownPreviewView` | SwiftUI views. Only the scroll container, scroll sync, nested-scroll routing and a few colours are AppKit. |
| Rich rendering | `RichContentRenderer` | WebKit works on iOS. The only differences are image types and the snapshot sizing. |
| Image resolution | `MarkdownParser` (image helpers) | `NSImage` drawing helpers need UIKit versions. |
| Editor ("Edit Text" / Source) | `SwashTextView`, `MarkdownEditorStyler`, `InteractiveTableView`, `BubbleMenuView` | Heavily AppKit: `NSTextView`, `NSTextBlock`, `NSTextAttachmentCell`, `NSFontManager`, `NSMenu`, `NSEvent`. This is the largest piece of work. |
| macOS only | `SparkleUpdater`, `ServicesProvider`, `DefaultAppManager`, Quick Look, thumbnail and share extensions | Each has an iOS equivalent (see below) or none is needed. |

## Feature parity map

| Feature | macOS | iPadOS | iOS (iPhone) |
|---|---|---|---|
| Documents | `DocumentGroup`, window per document | `DocumentGroup` document browser, multiple windows | `DocumentGroup` document browser |
| View modes | Source / Formatted / Split in the toolbar | All three. Split only at regular width; falls back to Source/Formatted when compact. | Source / Formatted toggle |
| Formatting commands | Format menu and shortcuts | The same `.commands` in the iPadOS menu bar and with hardware keyboards, plus the keyboard formatting bar | Formatting bar above the keyboard |
| Selection bubble menu | Floating bubble | Custom actions in the system edit menu (`UIEditMenuInteraction`) | Same |
| "/" block menu | `NSMenu` popup | Popover anchored at the cursor | List above the keyboard |
| Code-block language | `NSMenu` popup | `UIMenu` on the code block | Same |
| Interactive tables | NSTextView cells | UITextView cells; tap to edit, context menu for rows and columns | Same, scrolling horizontally |
| Smart paste (HTML → Markdown) | `NSPasteboard` | `UIPasteboard` | Same |
| Images next to the document | Grant Folder Access (`NSOpenPanel`), security-scoped bookmarks | Folder picker (`UIDocumentPickerViewController`) with persisted bookmarks | Same |
| Math and Mermaid | WKWebView snapshots | Same renderer | Same |
| Settings | Settings window | Settings sheet in the app | Same |
| Quick Look and thumbnails | Extensions | iOS Quick Look preview and thumbnail extensions | Same |
| Share into Swash | Share extension, Services menu | Share extension | Same |
| Widget | Quick Note widget | Widget for iOS families | Same |
| Shortcuts | App Intents | App Intents | Same |
| `swash://` links | Opened through `NSDocumentController` | Opened through `onOpenURL`, creating a document in the app's container | Same |
| Updates | Sparkle | App Store | App Store |
| Default Markdown app prompt | `DefaultAppManager` | Not applicable (document types declare "Open in") | Not applicable |

## Phases

### 1. Groundwork: no change for Mac users
- [x] Add `PlatformTypes.swift` (platform colours, fonts, images and SwiftUI bridges).
- [x] Wrap files that are entirely AppKit in `#if os(macOS)`.
- [x] Move shared files (preview, renderer, image helpers, folder access) onto platform types.
- [x] Keep the macOS build, spec tests and rich-render tests green.

### 2. iOS build that runs
- [x] Add iOS and iPadOS to the `Swash` target: SDK `auto`, deployment target, device family, iOS Info.plist (document types, opening documents in place, file sharing) and an iOS app icon.
- [x] Use platform filters so Sparkle and the four macOS extensions only build for macOS.
- [x] iOS app entry point: `DocumentGroup` with an iOS `ContentView`.
- [x] Source mode: a monospaced `UITextView` editor that keeps the document binding and undo.
- [x] Formatted mode: the shared `MarkdownPreviewView` in a `UIScrollView`-based container.
- [x] Split mode at regular width (iPad), and a mode toggle in the toolbar that adapts to size class.
- [x] Flavour picker, share sheet, settings sheet.
- [x] iOS simulator build in `pr-build.yml`.

**Phase 2 notes.** The formatting bar is hidden for Slack mrkdwn, whose delimiters the AST engine doesn't write yet. Preview table cells use a plain `TextField` when edited (they are read-only in the preview).

### 3. Styled editor ("Edit Text") on UIKit
- [x] Make `MarkdownEditorStyler` cross-platform. macOS keeps its `NSTextBlock`s unchanged. On iOS, quotes, alerts, code blocks and rules carry a `BlockDecoration` paragraph attribute that `StyledLayoutManager` paints (GOTCHAS #31). Italics use font descriptors on iOS.
- [x] `StyledUITextView`: a `UITextView` on TextKit 1 with hidden delimiters, list markers, task checkboxes (tap to toggle), code badges, alert icons, rendered math and Mermaid, and attachments for images and interactive tables.
- [x] `AttachmentOffsetMap` and the raw/storage offset bridging, shared in `EditorSupport.swift`.
- [x] Incremental restyling, ported from the macOS coordinator.
- [ ] iOS harness comparing incremental and full restyles (with the simulator tests in phase 6).

**Phase 3 notes.** Formatted mode on iOS is now the Edit Text editor, except for Slack mrkdwn, which still shows the read-only preview (the Mac styles Slack with a separate legacy path). Text is drawn at 17/14 of the Mac sizes (`MarkdownEditorStyler.fontScale`). Known gaps:
- UIKit has no per-range spell-check hook, so code isn't excluded from spell-checking on iOS.
- Links in the editor are edited, not followed.
- Undo across collapsed tables and images still needs testing on a device with a hardware keyboard.

### 4. Editing interactions
- [x] List continuation, indent/outdent, Backspace-unformat (in `UITextViewDelegate` and through key commands), in both editors.
- [x] Formatting bar above the keyboard (iPhone and iPad without a hardware keyboard).
- [x] Edit-menu formatting actions in place of the bubble menu.
- [ ] The code-language menu as a `UIMenu` (tapping the code badge).
- [ ] "/" block menu (popover on iPad, list above the keyboard on iPhone).
- [ ] Interactive tables on UIKit.
- [ ] Smart paste and rich copy with `UIPasteboard`.
- [ ] Hardware-keyboard shortcuts: `.commands` / `UIKeyCommand` matching the Mac.

### 5. System integration
- [ ] Folder access on iOS with the document picker and persisted bookmarks.
- [ ] `swash://new` and `swash://open`, and the Create Document intent, on iOS.
- [ ] iOS Quick Look preview and thumbnail extensions that reuse the shared renderer.
- [ ] iOS share extension.
- [ ] Widget for both platforms.

### 6. Testing and distribution
- [ ] iOS simulator test target for the editor (mirrors `Tests/EditorAudit`), run in CI.
- [ ] App Store Connect signing and a TestFlight workflow next to the macOS release workflow.
- [ ] README and the `swash-build-test` skill updated for iOS builds.

## Risks and open questions
- **Opening documents from code on iOS.** `DocumentGroup` has no `NSDocumentController.openDocument` equivalent. `swash://new` and the Create Document intent will probably create the file in the app's documents folder and open it with `openDocument` from the environment.
- **TextKit 1 on iOS.** `UITextView(usingTextLayoutManager: false)` is supported, but Apple puts its new work into TextKit 2. If TextKit 1 is deprecated, the editor will need a TextKit 2 layout path on both platforms.
- **Headless tests.** The existing harnesses are AppKit-only. Editor parity on iOS needs an XCTest target that runs on a simulator.
- **App icon.** The iOS icon currently reuses the macOS 1024 px artwork. It needs a full-bleed, opaque version before release.
