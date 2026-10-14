# Performance Audit

**Date:** 2026-10-14 · **Build audited:** `main` @ `ed603fc` (v1.8.6)
**Scope:** typing latency in every view mode, the preview, image and folder access, the Markdown parser, rich rendering (math and Mermaid), launch and document open, and the Quick Look, thumbnail, share and widget extensions.

## Summary

The core editing path is in good shape: incremental restyling and precomputed code ranges keep the text view well inside its budgets. The remaining cost comes from **repetition around that path**. One keystroke rebuilds the raw Markdown three times, parses the whole document two or three times, and re-evaluates `ContentView`, which runs word count, the folder-banner check and the share preview. In Split mode it also rebuilds and re-measures the whole preview and re-reads every image from disk. None of these costs is large alone, but together they grow with document size and are paid on every keystroke.

The parser is linear on realistic input, at about 5 MB/s. It has four quadratic paths that only matter on adversarial or unusual input.

## How this was measured

- **Editor:** the existing harness, `./Tests/EditorAudit/run_audit.sh perf`, hosts the real `SwashTextView` in an offscreen window.
- **Parser:** `Swash/Markdown/*.swift`, plus a Foundation-only copy of `MarkdownParser.codeRanges`, was compiled with `swiftc -O` (arm64, macOS 14) and timed on a 4,438-line realistic document and on pathological inputs. Times are the best of 5 runs.
- **Everything else** was found by reading the code and following each call path to its callers. The top findings were checked against the source. None of it has been profiled in the running app yet (see [Next steps](#next-steps)).

### Baseline

| Measurement | Result | Budget |
|---|---|---|
| Keystroke latency, styled mode, 2,251 lines (edit + incremental restyle + layout) | 16 ms | 50 ms |
| Full restyle, 111 lines | 2 ms | — |
| Full restyle, 551 lines | 10 ms | — |
| Full restyle, 2,201 lines | 42 ms | 500 ms |
| Parse, 4,438 lines (89K UTF-16 units) | 16.5 ms | — |
| Parse, 8,876 lines | 32.9 ms (linear) | — |
| Render to HTML, 4,438 lines | 4.5 ms | — |
| `codeRanges`, 4,438 lines (ASCII / non-ASCII) | 2.2 / 3.9 ms | — |
| `MarkdownEditingCommands.backspace`, 4,438 lines | **17.4 ms** (a full parse) | — |
| `MarkdownFormatting.activeBlockFormat`, 4,000-character selection | **44 ms** | — |

The keystroke benchmark times the text view alone. It does not include `ContentView`, the Split-view preview, image loading or the Slack flavor, which is where most of the findings below are.

## 1. Per-keystroke work in the editor

### 1.1 Raw Markdown rebuilt three times, and a dead early exit (High)

In styled mode, each keystroke calls `buildRawMarkdown` (a copy of the whole storage, plus one `replaceCharacters` per attachment) in three places:

- `textDidChange` (`SwashTextView.swift:995`), to publish `parent.text`.
- `updateNSView` (`SwashTextView.swift:706`), which SwiftUI calls because `parent.text` changed. It then also runs four whole-string `replacingOccurrences` passes and two whole-string `trimmingCharacters` calls before comparing.
- The async `highlightIncrementally` pass (`SwashTextView.swift:2114`).

The cheap guard in `updateNSView` (`lastStyledText != text`) never fires while typing. `lastStyledText` is only set at the end of the async styling pass (`:2065`), and `updateNSView` runs before that pass.

**Fix:** record the string published in `textDidChange` as `lastPublishedText`. In `updateNSView`, return early when `text == lastPublishedText`, and only normalise line endings when the strings differ.

### 1.2 The document is parsed two or three times per keystroke (High)

- `highlightIncrementally` parses the whole document (`SwashTextView.swift:2116`). `blockSummaries` then copies every top-level block as a substring, and `spellcheckExclusions` walks the whole tree (`:2172`).
- The selection change after an edit calls `updateSelectionRect`, which calls `linkFormatting(for: parent.text)` (`:888`). That cache misses because the text changed, so it runs a second full parse.
- `SwashEditorController.formatting(for:)` (`ContentView.swift:978`) keeps a third, separate cache of the same parse, used by the bubble menu.

**Fix:** keep the `MarkdownDocument` from `highlightIncrementally` and build `MarkdownFormatting(text:document:)` from it (the initializer already accepts a document). Have the coordinator, the link lookup and `SwashEditorController` share that one cache, keyed by text or `editGeneration`. Compare blocks by range and hash instead of copying substrings. For very large files, the parse can move to a background queue, since `Swash/Markdown` is Foundation-only, and be applied on main after checking `editGeneration`.

### 1.3 `TableTextAttachment.rawMarkdown` is recomputed on every read (Medium)

`InteractiveTableView.swift:880` compares the full `tableData` with `originalTableData` on every read. For an edited table it then re-serialises the table with `tableToMarkdown`. It is read by every `buildRawMarkdown` call (three per keystroke) and every `AttachmentOffsetMap` build (two per keystroke).

**Fix:** cache the serialised string and clear the cache in `tableData`'s `didSet`.

### 1.4 Backspace and Enter parse the whole document (Medium)

`MarkdownEditingCommands.backspace` calls `isInCode` (`MarkdownEditingCommands.swift:204`) before its cheap line checks. `isInCode` (`:37`) builds a new `MarkdownFormatting`, which is a full parse: 17.4 ms at 4,438 lines, for almost every Backspace even when nothing changes. `newline` does the same (`:48`).

**Fix:** run the `caretInLine <= contentOffset` guards first. Answer `isInCode` from the coordinator's cached code ranges or document (§1.2) instead of parsing again.

### 1.5 Scroll restored 80 ms after every styling pass (Medium)

`finishStyling` (`SwashTextView.swift:2058`) schedules an `asyncAfter(0.08)` that scrolls back to the saved origin after **every** pass, keystrokes included. While typing near the bottom of the window, this can fight caret autoscroll and momentum scrolling.

**Fix:** only restore the scroll position after a full pass that replaced the storage.

### 1.6 Selection rectangle recomputed on every scroll frame (Medium)

`scrollViewDidScroll` (`SwashTextView.swift:1035`) calls `updateSelectionRect` on every bounds change. That calls `linkFormatting(...).link(at:)`, which walks the whole tree with no early exit (`MarkdownFormatting.swift:126`). For Slack it runs the `LinkDetector` regexes over the whole document. It also calls `boundingRect` when the selection is empty.

**Fix:** while scrolling, only reposition the existing rectangle using the stored raw selection and active link. Skip the work when the selection is empty and no link is active.

### 1.7 Table cell edits force a full restyle (Medium)

A cell edit sets `forceFullRestyle = true` (`SwashTextView.swift:2006`), so the next keystroke in the main editor rebuilds every table hosting view and reloads every image. Each cell keystroke also rebuilds the whole raw Markdown and walks every attachment to find its own cell (`InteractiveTableView.swift:838`).

**Fix:** a cell edit only shifts later offsets. Invalidate the offset map and patch `lastBlocks`, as `refreshRichPreviews` already does, instead of forcing a full pass. Store the attachment's character index rather than searching for it.

### 1.8 Source mode restyles the whole storage per keystroke (Medium)

In Source and Split modes, `textDidChange` (`:1005`) calls a path that runs `setAttributes` over the full range (`SwashTextView.swift:2253`). That invalidates layout for the whole document and is followed by a full `codeRanges` scan.

**Fix:** set `typingAttributes` once, only restyle on a full pass, and update the code-block cache around the edited range.

### 1.9 Slack flavor restyles everything on every keystroke (High, Slack only)

`highlightIncrementally` returns `false` for `.slack` (`SwashTextView.swift:2110`). Each keystroke therefore:

- replaces the whole storage when it contains attachments (`:1361`), which discards all layout;
- removes and recreates every table `NSHostingView` (`:1349`, `:2001`);
- reloads every image (§3);
- compiles regexes inside the per-line loop: alerts at `:1602`, tasks at `:1653` and footnotes at `:1705`, plus about 8 more per pass in `applyRegex` (`:2278`) and the link and image scans.

**Fix:** make every pattern a `static let NSRegularExpression`. Apply the same top-level block diff to Slack, using a blank-line paragraph split. At minimum, wait about 100 ms after typing stops before restyling Slack.

### 1.10 Allocations while drawing (Low)

- `drawBackground` builds a new alert symbol image on every draw (`AlertIconInfo.image`, `MarkdownEditorStyler.swift:78`, used at `SwashTextView.swift:202`).
- List markers allocate a font, an attributes dictionary and a text measurement per marker per draw (`:221`).
- `CodeBadgeInfo.rect` measures its title every time.
- `textStorage.range(of:block,at:)` (`:148`) scans the block's whole extent on every draw.

**Fix:** cache the images and sizes as static values. Store the block range in the attribute when styling.

### 1.11 Offset bookkeeping is O(exclusions × attachments) (Low)

`cachedStorageCodeBlocks` (`SwashTextView.swift:2048`) maps every exclusion through the linear `storageRange` on every keystroke. `AttachmentOffsetMap.rawLocation` is also linear in the number of spans.

**Fix:** walk the sorted exclusions and spans once together, or binary-search over prefix sums.

## 2. ContentView and the preview

### 2.1 `ContentView.body` does whole-document work per keystroke (Medium)

Every change to `document.text` re-evaluates `body`, which runs:

- **Word count** (`ContentView.swift:396`, `:1518`): a full trim, `components(separatedBy:)` (one String per word) and a full grapheme `count`.
- **Folder banner** (`:93`, via `MarkdownParser.unreadableRelativeFolder` at `MarkdownParser.swift:235`): a `stat` call per evaluation. While access is missing it also compiles a regex, scans the whole document and calls `isReadableFile` for each relative image.
- **Share link** (`:205`): wraps the whole document in a `Text`. `sharePreviewImage` (`:275`) looks up an `NSWorkspace` icon and draws it with `lockFocus` on every evaluation. `documentTitle` (`:253`) can split every line of an untitled document.
- **`effectiveBaseURL`** (`:89`): when there is no `fileURL`, it is looked up through `NSDocumentController.document(for:)` on every evaluation.

Because `selectionRect` is republished on each scroll tick while text is selected, all of this also runs on every scroll frame.

**Fix:** compute stats and the banner state in `onChange(of: document.text)`, about 300 ms after typing stops, and on folder-access changes. Store them in `@State`. Count words in one pass over the scalars and use `utf16.count` for length. Make the share preview image a `static let`. Cache `effectiveBaseURL` when the window attaches.

### 2.2 Code-range scans repeated in the bubble menu (Medium)

`determineActiveCodeFormat` (`ContentView.swift:1359`) runs two full `codeRanges` scans. It is called from the overlay (`:294`), `determineActiveFormats` and `determineBubbleMenuContext` (`:733`), and the last of these also calls `isSelectionInsideCodeBlock`. That adds up to about seven O(n) scans per `body` evaluation while the menu is visible.

**Fix:** compute the code format once per evaluation from the shared document (§1.2).

### 2.3 Split view rebuilds and re-measures the whole preview per keystroke (High)

- `ParseCache` (`MarkdownPreviewView.swift:203`) misses on every edit and parses everything again.
- `MarkdownBlockList` uses `ForEach(..., id: \.offset)` with `AnyView` wrappers (`:266`), and every parse creates new `MarkdownNode` objects. SwiftUI therefore can't tell which blocks are unchanged and re-renders all of them.
- `PreviewScrollView.updateNSView` (`:150`) sets `rootView` and reads `hostingView.fittingSize`, which lays out the whole document synchronously.

**Fix:**

- Wait 150–250 ms after typing before updating the preview: keep a `@State` copy of the text and update it from a `.task(id: text)` that sleeps first.
- Give blocks stable identities (a hash of the block's source plus an occurrence index), and make `MarkdownBlockView` `Equatable` on its source.
- Replace `AnyView` with an `@ViewBuilder` switch.
- Size the hosting view with Auto Layout constraints, or only measure when the content changed.

### 2.4 HTML blocks and table cells re-parsed on every evaluation (Low)

- Each HTML block runs `HTMLToMarkdown.convert`, a full parse and a text walk inside `body` (`MarkdownPreviewView.swift:366`).
- `InlineMarkdownText` (`:979`) parses its cell in `body`. `InteractiveTableView` keeps hover and editing state at the top level, so any change re-renders every cell.

**Fix:** cache the conversion by HTML string and the cell parse by text. Move cells into an `Equatable` subview.

## 3. Images and folder access

### 3.1 Images are loaded and scaled on the main thread with no cache (High)

- **Editor:** every restyle of a block with an image calls `MarkdownParser.resolveImage` (`SwashTextView.swift:2021`). That tries up to four paths with synchronous `NSImage(contentsOfFile:)`, then redraws the image with `lockFocus` in `scaleImageForEditor`. Incremental styling also restyles the block before the edited one, so typing next to an image reloads it on every keystroke. A full restyle (open, mode switch, flavor change, table edit, appearance change) reloads every image.
- **Preview:** `resolvedNSImage` is a computed property in `body` (`MarkdownPreviewView.swift:845`). It tries up to six path variants. Because every preview block re-renders (§2.3), every local image is reloaded on every keystroke in Split mode.

**Fix:** add an `NSCache` keyed by resolved path and modification date for the source image, and by path and width for the scaled version. Clear it when folder access is granted. In the preview, load images in `.task(id: url)` off the main thread.

### 3.2 `ensureAccess` repeats work and leaks access handles (Medium, also a correctness issue)

Every image lookup calls `FolderAccessManager.ensureAccess` (`MarkdownParser.swift:206`, `FolderAccessManager.swift:76`). When the folder isn't readable, it reads the bookmark dictionary from `UserDefaults`, resolves the bookmarks again, and calls `startAccessingSecurityScopedResource()` again **without a matching stop**. The access count therefore grows with every render.

**Fix:** check `activeSecurityScopedURLs` before resolving anything, and keep the bookmark dictionary in memory.

### 3.3 All saved folder bookmarks resolved synchronously when the first window opens (Medium)

`FolderAccessManager.shared` is first used through `@ObservedObject` in `ContentView.swift:85`. Its initializer (`FolderAccessManager.swift:23`) resolves every saved bookmark and starts security-scoped access to each one on the main thread. The list is never pruned.

**Fix:** resolve each folder lazily in `ensureAccess`, or on a background queue. Remove stale or failing entries, and stop access for folders that are no longer used.

## 4. Math and Mermaid rendering

The renderer already does the right thing at the base level: there is one shared offscreen `WKWebView`, created on first use, with an LRU cache. `mermaid.min.js` (5.2 MB) is only loaded for the first diagram. `warmUp()` is never called, so nothing loads at launch.

### 4.1 Stale render requests pile up while typing (Medium)

Each keystroke inside `$…$`, `$$` or a Mermaid block queues a new request (`RichContentRenderer.swift:115`, `:226`). Requests are never cancelled, so the queue renders every intermediate state in turn and fills the 400-entry cache with them. Every completed render posts `didRender`, which triggers `refreshRichPreviews` → `highlightMarkdown` (a full parse, §1.2) and re-evaluates every pending `MarkdownInlineView` (`MarkdownPreviewView.swift:948`). Opening a document with N formulas causes N restyle passes.

**Fix:** combine or delay requests per block, and drop queued requests that nothing refers to any more. Post `didRender` once when the queue empties.

### 4.2 Renders are strictly sequential (Low)

Each item makes one JavaScript round trip and one `takeSnapshot(afterScreenUpdates: true)` (`RichContentRenderer.swift:160`), so 100 formulas need 100 snapshots in a row. `cacheOrder.removeFirst()` is O(n), and `mermaid.initialize` runs on every render.

**Fix:** render inline formulas in batches with one snapshot, or add a second web view.

## 5. Markdown parser

Already fine: the block parser works on a `[UInt16]` buffer with no O(n) index offsets; emphasis handling uses `openersBottom` correctly (20,000 `*` in 0.07 ms); backtick and `$` scanning are guarded; inline regexes are static and anchored; the entity table is built lazily; HTML rendering is linear.

### Pathological inputs

| Input (N repetitions) | 5k | 10k | 20k |
|---|---|---|---|
| `*a ` | 26 ms | 62 ms | 175 ms |
| `[` | 5 ms | 16 ms | 52 ms |
| `a_ b` | 30 ms | 77 ms | 253 ms |
| `&amp; ` | 17 ms | 57 ms | 139 ms |
| `< ` | 18 ms | 59 ms | 146 ms |
| N/2 `[` then N/2 `[a](b)` | 49 ms | 93 ms | **328 ms** |
| N/4 reference definitions in one paragraph | 15 ms | 46 ms | 154 ms |
| N/10 nested `>` on one line | 6 ms | 25 ms | 101 ms |

### 5.1 Merging adjacent text nodes is quadratic (Medium)

`mergeText` (`MarkdownInlineParser.swift:753`) runs `setTextMap(c, (textMap(c) ?? []) + (textMap(next) ?? []))`, copying the whole growing offset map for every merged node. Every unmatched `* _ [ ] ! < &`, entity and escape creates its own text node, so a run of k nodes costs O(k²).

**Fix (measured):** remove the map from the dictionary once, append to it in place, and write the literal and map back once per run. The 20k cases above fell from 175 / 52 / 253 / 139 / 146 ms to 31 / 12 / 31 / 36 / 40 ms, now linear.

### 5.2 Weak `parent` / `previous` references (Medium)

The weak references at `MarkdownNode.swift:105` and `:109` give every node a side table, which sends all of its retains and releases down the slow path. That accounted for about 20% of profile samples.

**Fix (measured):** `unowned(unsafe)` cut the parse from 16.5 to 13.1 ms (−21%) and `activeBlockFormat` from 44 to 31 ms. This is only safe if no node outlives its `MarkdownDocument`. The safer option is an arena: a node array with integer links, owned by the document.

### 5.3 `activeBlockFormat` walks the whole tree once per selected line (Medium)

`isCodeLine` (`MarkdownFormatting.swift:388`) walks every node for each line, so `activeBlockFormat` (`:400`) and `toggleBlock` cost O(lines × nodes): 44 ms for a 4,000-character selection, on every selection change.

**Fix:** collect the code-block ranges once, sorted, and binary-search them. More generally, `walk` in `nodes(intersecting:)`, `codeBlock`, `link(at:)` and `inlineContainers` should skip subtrees whose range doesn't overlap the target.

### 5.4 Deactivating link openers is quadratic (Low)

Each matched link walks the whole bracket stack to deactivate earlier openers (`MarkdownInlineParser.swift:736`). This is the same issue commonmark.js has, and costs 328 ms at 10k.

**Fix:** use cmark's "no link openers below here" marker, or stop at the first opener that is already inactive.

### 5.5 Consecutive link reference definitions are quadratic (Low)

Each definition rebuilds `s.content` from the remaining text (`MarkdownBlockParser.swift:996`), and `parseReference` creates an NSString of the whole remaining paragraph (`MarkdownInlineParser.swift:147`).

**Fix:** pass a start offset instead of copying, and trim once at the end.

### 5.6 `touch()` walks every ancestor on each container marker (Low)

`touch()` (`MarkdownBlockParser.swift:270`, called from `:408`, `:500`, `:716` and elsewhere) costs O(depth) per marker, so O(depth²) per line. 2,000 nested `>` take 101 ms for 4 KB of input.

**Fix:** call `touch(tip)` once at the end of `incorporateLine`, or work out end offsets from the last child during `finalize`.

### 5.7 Regexes compiled on every call (Low)

A `range(of:options: .regularExpression)` call compiles its pattern each time. Measured cost: about 1.1 µs per call, against 0.27 µs for a static `NSRegularExpression` and 0.04 µs for a hand-written scan.

Hot sites:

- **Table delimiter cells:** `MarkdownBlockParser.swift:742`, once per cell. `startTable` was about 8% of parse samples, and it also copies the whole paragraph content (`:748`).
- **Other parser sites:** HTML block finalize (`:940`), alerts (`:1027`), `:879`, `MarkdownMath.swift:60`, and `HTMLToMarkdown.swift:141` and `:185`.
- **In `MarkdownParser.swift`:** `parseATXHeading` (`:119`), `extractLinkReferenceDefinition` (`:126`, which builds an `NSRegularExpression` for every line on the Slack path), `cleanImageURLAndTitle` (`:141`) and `unreadableRelativeFolder` (`:243`).

**Fix:** make the patterns `static let`. Replace `^:?-+:?$` and `(\n *)+$` with hand-written scans. In `startTable`, scan backwards in place instead of copying.

### 5.8 Per-node allocations in the inline parser (Low)

Every special character creates a `MarkdownNode`, a `String` built through `String(utf16CodeUnits:)` from a temporary array (`MarkdownInlineParser.swift:88`), and a `[Int]` offset map stored in a `[ObjectIdentifier: …]` dictionary (`:63`, `:111`). Each paragraph also builds an NSString of its content (`:126`). `recordFootnoteOrder` (`:772`) calls `Array.contains` for each reference, which is O(F²).

**Fix:** store each map as a start and length into the paragraph's map, kept on the node. Build literals lazily or with `String(decoding:as: UTF16.self)`. Track footnotes with a `Set` alongside the array.

### 5.9 `codeRanges` constant factors (Low)

`codeRanges` (`MarkdownParser.swift:747`) splits the text with `components(separatedBy:)` (one String per line). Each line is then bridged to NSString for its length, trimmed, and processed with Character-level `drop` and `count` in `parseOpeningCodeFence`. `isListItemLine` runs a regex up to twice per prose line, and `codeSpans` reads characters one at a time through the bridged NSString.

**Fix:** scan a single `Array(text.utf16)` buffer. This should be at least 3× faster, but removing the repeated calls (§1.2, §2.2) matters more.

## 6. Launch, document open and extensions

### 6.1 Quick Look has no size limit and parses on the main thread (High)

Each preview (each press of the space bar) reads the whole file with `Data(contentsOf:)` and builds the full `MarkdownPreviewView` on the main thread (`SwashQuickLookExtension/PreviewViewController.swift:21`, `:32`). Any math or Mermaid in the file starts a `WKWebView` inside the Quick Look process (`MarkdownPreviewView.swift:656`, `:1128`). That means launching a WebContent process, possibly parsing the 5 MB Mermaid script, and waiting up to the 15 s timeout (`RichContentRenderer.swift:90`).

**Fix:**

- Read at most the first 256 KB and add a "truncated" note.
- Parse off the main thread.
- In Quick Look, show math and Mermaid source as code blocks instead of rendering them.

### 6.2 Quick Look bundles all of `Swash/Rendering/` (Medium, bundle size)

The Quick Look target's membership exceptions (`project.pbxproj:82`) only exclude app-only Swift files, so the extension also ships about 6 MB of KaTeX, Mermaid and fonts.

**Fix:** after §6.1, exclude `Rendering/*` from the Quick Look target.

### 6.3 Flavor detection runs 9 new regexes over the whole file on open (Low)

`detectFlavor` (`MarkdownParser.swift:389`, called from `SwashDocument.swift:40`) compiles its regexes on each call and scans the entire document.

**Fix:** make the regexes `static let`, only scan the first ~32 KB, and stop once one flavor clearly leads.

### 6.4 Default-app check blocks the main thread at launch (Low)

`SwashApp.swift:16` and `DefaultAppManager.swift:24`, `:90`, `:112` make synchronous LaunchServices lookups twice, then show a `runModal()` prompt while documents opened from Finder are still loading.

**Fix:** show the prompt after the first window appears, and reuse the cached `isDefaultAppStatus`.

### 6.5 Thumbnails read the whole file (Low)

`ThumbnailProvider.swift:16` reads the full file to draw about 500 characters (`:44`).

**Fix:** read only the first ~4 KB with `FileHandle.read(upToCount:)`.

### 6.6 Already fine

- Thumbnails draw plain text without parsing or WebKit.
- The widget uses `policy: .never`.
- Sparkle defers its first update check.
- Release builds use `SWIFT_COMPILATION_MODE = wholemodule` and the default `-O`.
- `SwashDocument.fileWrapper` only encodes UTF-8.
- KaTeX preloads about 300 KB of fonts on first use, which is an acceptable one-off cost.

Optional: set `DEAD_CODE_STRIPPING = YES` explicitly, and check it with `xcodebuild -showBuildSettings -configuration Release`.

## Recommended plan

### Phase A: per-keystroke work (small, low risk) — done

| # | Change | Sections | Status |
|---|---|---|---|
| A1 | `updateNSView` returns early when `text` matches the last published text | §1.1 | Done |
| A2 | One shared parse per edit, used by styling, link lookup, the bubble menu and code checks | §1.2, §2.2 | Done in the editor; the bubble menu's `codeRanges` scans (§2.2) remain |
| A3 | Cache `TableTextAttachment.rawMarkdown` | §1.3 | Done |
| A4 | Run cheap guards before `isInCode` in Backspace and Enter, and use the cached document | §1.4 | Done |
| A5 | Image `NSCache`, and remove the repeated `ensureAccess` work and access leak | §3.1, §3.2, §3.3 | Done; bookmarks also resolve lazily (§3.3). The preview still loads images on the main thread (B1) |
| A6 | Only restore the scroll position after full passes | §1.5 | Done |

Measured with the extended `run_audit.sh perf` (best of the runs, `main` → Phase A):

| Benchmark | `main` | Phase A |
|---|---|---|
| Keystroke, styled, 2,251 lines | 19 ms | 15 ms |
| Backspace in a paragraph, 4,401 lines | 10.8 ms | 0.01 ms |
| Keystroke next to a 2400×1600 local image | 30 ms | 7 ms |

### Phase B: views and rendering (medium) — mostly done

| # | Change | Sections | Status |
|---|---|---|---|
| B1 | Delay preview updates until typing pauses, give blocks stable identities, remove `AnyView` and the synchronous `fittingSize` | §2.3 | Done. The preview updates 200 ms after typing, and blocks are keyed by source and `Equatable`. `fittingSize` only runs when the content or width changes, or after a render or access grant lands. Nested lists, list items and footnotes still use `AnyView` |
| B2 | Move word count, the banner check and the share preview out of `body` | §2.1 | Done. The banner check runs from a task, the share icon is static, and the title scan stops early. The window's document URL is cached. Word count is debounced in the outline/statistics feature work (#19) |
| B3 | Restyle Slack incrementally, with static regexes | §1.9 | Partial. Slack restyles 120 ms after typing pauses and patterns are compiled once. The incremental block diff for Slack is not done |
| B4 | Cancel or combine stale math and Mermaid requests, and post `didRender` once per batch | §4.1 | Done. Requests are coalesced per editor block and dropped when cancelled, `didRender` is throttled, and eviction is batched. Batched snapshots (§4.2) are not done |
| B5 | Quick Look size limit, background parsing, no WebKit | §6.1, §6.2, §6.5 | Done. Quick Look reads at most 256 KB, parses in the background and doesn't bundle `Rendering/`. Thumbnails read 4 KB |
| B6 | Lighter scroll handling, table cell edits, Source-mode restyle | §1.6–§1.8 | Done |

Measured with `run_audit.sh perf` (before Phase B → after):

| Benchmark | Before | After |
|---|---|---|
| Split preview, 10 quick keystrokes, 900 lines (CPU) | 521 ms | 114 ms |
| Slack full restyle, 900 lines | 36 ms | 33 ms (one pass per typing pause instead of per keystroke) |

### Phase C: parser hardening

Fix in this order: `mergeText` (§5.1), `activeBlockFormat` (§5.3), node references or an arena (§5.2), link openers (§5.4), reference definitions (§5.5), `touch()` (§5.6), regexes (§5.7).

## Next steps

Extend `Tests/EditorAudit/PerfRunner.swift` to cover the paths the current benchmark misses, so each phase can be measured and protected from regressions:

- typing through `ContentView` in Split mode, including the preview;
- typing next to images;
- typing in Slack flavor;
- Backspace and Enter on a large document;
- `activeBlockFormat` on a large selection.

Add the pathological parser inputs from §5 to `./scripts/run_commonmark_spec.sh`, with linear-growth assertions.

After Phase A, profile the running app with Instruments (Time Profiler and SwiftUI) on a document of about 5,000 lines in each view mode, to confirm the remaining order of priorities.
