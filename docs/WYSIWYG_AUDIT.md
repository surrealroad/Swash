# WYSIWYG "Edit Text" Mode — Audit & Gap Analysis

**Date:** 2026-10-02 · **Build audited:** `main` @ `f31d683` (v1.4.1), Debug build
**Target experience:** Notion-style block editing with contextual bubble-menu actions, rendering consistent with the Preview pane.

All findings below come from building and running the app's actual code: the real `SwashTextView`, `ContentView` and `BubbleMenuView` are hosted in live AppKit windows, with text entered, selected and edited through them. Each finding can be reproduced with:

```bash
./Tests/EditorAudit/run_audit.sh all
```

Reports and side-by-side editor/preview PNGs are written to `build/editor-audit/`.

> **Phase 0 status (2026-10-02, branch `fix/wysiwyg-phase0`):** all six Phase 0 items in §8 are done and covered by asserting regression tests in `Tests/EditorAudit/` (`run_audit.sh all` exits non-zero on any regression).
> - D1–D5 are fixed.
> - Bubble edits can be undone.
> - Restyling takes 56 ms at 2,200 lines (was 26,949 ms).
> - Code spans of any backtick length and indented code render and are no longer interpreted.
> - `~~~` fences, `1)` lists and task items are recognised by the bubble menu.
> - Prose containing `|` is no longer treated as a table.
> - The italic-underscore toggle is fixed, selections are whitespace-trimmed, multi-line selections are wrapped per line, and code fences are placed on their own lines.
> - The duplicate dropdown chevrons are removed.
>
> **Phase 1 status (branch `feat/wysiwyg-phase1-ast`):** done. One parser now drives the editor, the Preview, Quick Look, table cells and the bubble menu.
> - **Parser:** Swash's own CommonMark 0.31.2 + GFM parser (`Swash/Markdown/`), with exact UTF-16 node and marker ranges. It was chosen over swift-markdown, which lacks footnotes, extended autolinks, alerts and front matter.
>   - Conformance: 652/652 CommonMark examples, 50/50 GFM extension examples, marker-range checks, 3,000 fuzzed inputs and pathological-input timing (`./scripts/run_commonmark_spec.sh`).
> - **Edit Text:** styled from the tree (`MarkdownEditorStyler`). Slack mrkdwn keeps the legacy path.
> - **Preview, Quick Look and table cells:** rendered from the tree.
> - **Bubble menu:** uses `MarkdownFormatting` for context, active states, inline toggles (exact-marker removal, merging overlapping spans), links and quote-preserving block toggles.
> - **Old parser:** the block parser (`MarkdownParser.parse`) has been removed, and the GFM fixture suite now runs against the new tree.
> - **Remaining for Phase 2:** keyboard behaviours (list continuation, Tab/Backspace, ⌘B/⌘I), caret atomicity around hidden markers, clickable checkboxes, HTML paste, and a selection-less block menu.
> - **Remaining for Phase 3:** HTML rendering, math, Mermaid, a code-block language badge, and incremental (per-block) re-styling.
>
> **Phase 2 status (branch `feat/wysiwyg-phase2`):** done.
> - **Enter, Tab, ⇧Tab, Backspace:** continue, nest and un-format lists, to-dos and quotes.
> - **Caret:** skips hidden markers.
> - **Shortcuts and a Format menu:** ⌘B/⌘I/⌘E/⌘K/⌘⇧X, headings, lists, quote, code block.
> - **Clickable to-do checkboxes.**
> - **Rich paste:** HTML and RTF paste as Markdown, and Swash-to-Swash copy is lossless.
> - **"/" block menu** for inserting blocks.
> - **Code-block language badge** with a language menu.
> - **Coverage:** unit checks run in `./scripts/run_commonmark_spec.sh`; end-to-end cases run in `./Tests/EditorAudit/run_audit.sh`.
> - **Remaining (Phase 3):** HTML/math/Mermaid rendering, incremental (per-block) restyling, and keeping the code badge clear of long first lines.
>
> **Phase 3 status (branch `feat/wysiwyg-phase3`):** done, except real math typesetting and Mermaid diagrams. Both need a rendering engine (for example a WebView with KaTeX and mermaid.js, or a dependency), which is still a decision to make.
> - **Inline HTML** (`<kbd>`, `<sub>`/`<sup>`, `<mark>`, `<u>`, `<s>`, `<b>`/`<i>`, `<small>`, `<img width>`) renders in both panes.
> - **Preview HTML blocks:** `<details>` disclosures, HTML converted to Markdown, and image-only blocks at their width.
> - **Math:** `$…$` and `$$` blocks are parsed and styled, protected from Markdown, with a Unicode rendering in the Preview.
> - **Editor polish:** alerts show icons, and code badges keep clear of long first lines.
> - **Incremental restyling:** keystroke latency at 2,250 lines dropped from ~70 ms to ~20 ms.
>
> The sections below describe the pre-fix state.

---

## 1. Executive summary

| Area | Verdict |
| :--- | :--- |
| **Data integrity** | ❌ **Three ways to corrupt a document**: bubble-menu actions after any image/table/link-before-selection edit the wrong text; an image inside a table cell deletes text after the table; untouched tables are silently re-formatted on the first keystroke. |
| **Rendering parity (Editor vs Preview)** | ❌ Of the 48 constructs in the matrix (§4), the editor renders only 15 correctly. Editor and Preview disagree on 18, and 15 are wrong or unsupported in both. |
| **Inline rendering** | ⚠️ Basic `**`/`*`/`~~`/`` ` `` work in isolation; nesting, escapes, code-span contents, multi-line spans, reference links, autolinks and linked images break. |
| **Block rendering** | ⚠️ Headings, fenced code, tables, alerts and simple lists work; nested/continued lists, nested quotes, indented code and front-matter are wrong in one or both panes. |
| **Editing behaviour** | ❌ None of the Notion-style keyboard behaviours exist: no list continuation, Tab-indent, Backspace-to-unformat, ⌘B/⌘I or checkbox toggle. The caret also stops on invisible marker characters. |
| **Bubble menu** | ⚠️ The core toggles work for plain paragraphs. Edits are not undoable, the context detection is heuristic and often wrong, and there are no task, divider, callout or "Turn into" actions. |
| **Performance** | ❌ The whole document is re-styled on every keystroke at O(n²) cost: **0.43 s per keystroke at 550 lines, 27 s at 2,200 lines.** |
| **Test coverage** | ⚠️ The 50 "passing" spec tests assert only that the parser produced *some* block and that a PNG was written. The editor output is never asserted. |

---

## 2. Root causes (architecture)

Most of the symptoms trace back to five structural decisions.

1. **Four separate markdown interpretations exist and disagree:**
   - `MarkdownParser.parse` builds the block model for the **Preview**.
   - Apple's `AttributedString(markdown:)` renders **Preview inline** text, following CommonMark rules.
   - `SwashTextView.Coordinator.highlightMarkdown` styles the **Editor** with ~25 independent regexes and a second line-by-line block scanner.
   - `ContentView.parseLinePrefix` / `isSelectionInsideCodeBlock` and `LinkDetector` drive **bubble-menu context and actions** with their own prefix and backtick heuristics.

   As a result, no construct is guaranteed to look, or behave, the same across the panes.
2. **Markers are "hidden", not removed.** Syntax characters stay in the text storage with a 0.01 pt clear font. The caret can stop on them, Backspace deletes them, typing lands inside them, and the arrow keys "stall" (§5).
3. **Attachments make text-storage offsets differ from raw-markdown offsets.** A table or image is replaced by a single U+FFFC attachment character. `textViewDidChangeSelection` publishes storage offsets, but `ContentView` applies them to `document.text`, which is raw markdown. Every bubble action after an attachment therefore edits the wrong span (§3).
4. **Bubble actions rewrite the whole document string.** They assign `document.text = …`, which causes `updateNSView` to run `textView.string = text`. This bypasses the `NSTextView` undo manager, so no bubble edit can be undone, and the full re-layout loses typing attributes.
5. **Full restyle on every change, with quadratic helpers.** `isRangeInCodeBlock` rescans the entire document for fences once per regex match, and it is called for every match of every inline pattern. It also only recognises fences with ``` or ~~~ at the start; it ignores indented code and code spans.

---

## 3. P0 — Data-corruption bugs (verified)

| # | Repro | Result |
| :--- | :--- | :--- |
| D1 | `![logo](missing.png) Select target word here.` → select **target** → Bold | `![logo](m**issing**.png) Select target word here.` (image URL corrupted; the selected word is untouched) |
| D2 | Table, then paragraph → select a word in the paragraph → Bold | `**\|---\|-**--\|`: the table delimiter row is corrupted |
| D3 | `![i](x.png) add link here` → select **link** → Add Link `https://c.com` | `![i](https://c.com) add link here`: the **image URL is overwritten**. The link detector also reports the image as the "active link". |
| D4 | `\| A \| B \|…\| ![i](x.png) \| text \|` followed by `After table paragraph` | The raw markdown becomes `…\| ![i](x.png) \| text \|ble paragraph`. **15 characters after the table are deleted.** The image attachment inside the table range is replaced first, which leaves the table's stored range stale (`highlightMarkdown`, pending-attachment pass). |
| D5 | Open `\|a\|b\|\n\|-\|-\|\n\|1\|2\|` and type one character anywhere | Every table in the file is re-padded and re-delimited (`\| a   \| b   \|`, `\| --- \|`, outer pipes added). The file churns without any table being touched. |

The fix for D1–D3 is one change: translate selection ranges between storage and raw offsets, or better, stop collapsing source into attachments (§8). D4 is a range-overlap bug: image matches inside a table range must be skipped.

---

## 4. Rendering matrix

✅ correct · ⚠️ partial/visually off · ❌ wrong or unsupported · *(E)* = Edit Text (WYSIWYG), *(P)* = Preview/split pane

### 4.1 Inline

| Construct | Editor (E) | Preview (P) | Notes |
| :--- | :---: | :---: | :--- |
| `*i*` `_i_` `**b**` `__b__` `***bi***` `~~s~~` | ✅ | ✅ | |
| Bold containing italic `**a *b* c**` | ❌ | ✅ | E shows the outer `**` literally and styles only the inner span. |
| Italic containing bold `*a **b** c*` | ❌ | ✅ | Same failure. |
| Emphasis spanning a soft line break | ❌ | ✅ | All inline regexes exclude `\n`. The bubble menu can still *produce* `**one\nline**` (§6). |
| Backslash escapes `\*` `\#` | ❌ | ✅ | E italicises `\*not italic\*` and shows the backslashes. |
| Code span contents treated literally | ❌ | ✅ | `` `__init__` `` shows as bold **init** with the underscores hidden; `` `[x](y)` `` becomes a live link. The code-exclusion check only covers fenced blocks. |
| Double-backtick span ``` ``a `b` c`` ``` | ❌ | ✅ | E shows `` `a tick here` `` with no code styling. |
| Inline code/bold inside headings | ❌ | ⚠️ | E resets **bold** to 14 pt inside an H2 (visibly shrinks) and code loses monospace. P drops monospace. |
| Link `[t](url "title")` | ✅ | ✅ | |
| URL with parentheses `…/Foo_(bar))` | ❌ | ✅ | E renders `wiki)` and the link target is truncated. |
| Reference links `[t][ref]`, `[ref][]`, `[ref]` | ❌ | ✅ | E shows them raw. Definitions stay visible as raw lines in E. |
| Autolinks `<https://…>` `<me@x.com>` | ⚠️ | ✅ | E links the URL but leaves the `<` `>` visible. |
| Bare URLs / `www.` / email | ✅ | ✅ | |
| Linked image / badge `[![a](img)](url)` | ❌ | ❌ | Both render `[` + image + `](https://ci.com)`. This breaks every README badge row. |
| Inline image within a sentence | ⚠️ | ⚠️ | E attaches inline. P breaks the paragraph into stacked rows around the image. |
| Hard break (two spaces / `\`) | ❌ | ⚠️ | E shows the trailing `\`. P treats *every* newline as a hard break (`inlineOnlyPreservingWhitespace`), so soft wraps diverge from GFM. |
| Footnote refs `[^1]` | ⚠️ | ✅ | E shows a superscript `[1]` with brackets. It isn't clickable. |
| Inline HTML `<kbd> <sub> <sup> <br> <mark>` | ❌ | ❌ | Shown as literal tags in both. |
| HTML comments `<!-- -->` | ❌ | ❌ | Visible in both. |
| `==highlight==`, `:emoji:`, `$math$` | ❌ | ❌ | Unsupported (extensions; decide scope). |

### 4.2 Blocks

| Construct | Editor (E) | Preview (P) | Notes |
| :--- | :---: | :---: | :--- |
| ATX headings H1–H6, closing `##` | ✅ | ✅ | |
| Setext headings | ✅ | ✅ | |
| Setext false positive: `- item` followed by `---` | ❌ | ✅ | E makes the *list item* a 20 pt H2 (with a visible `- `) and hides the rule. Typing `---` under a paragraph instantly converts it to H2 and makes the rule vanish. |
| YAML front matter | ❌ | ❌ | Both render `title:`/`tags:` as an H2 between rules. |
| Fenced code ``` / ~~~ | ✅ | ✅ | E hides the fences **and the language**. There's no language badge, so the only way to see or change it is the bubble menu. P shows a header. |
| Markdown inside fenced code | ✅ | ✅ | |
| Indented (4-space) code | ❌ | ✅ | E applies no code styling and still parses `**x**` inside it. |
| Unclosed fence | ✅ | ✅ | Consistent: it runs to the end of the document. |
| Thematic breaks `***` `- - -` `___` | ✅ | ✅ | |
| Bullets `-` `*` `+` | ✅ | ✅ | |
| Nested bullets (2-space) | ⚠️ | ⚠️ | E keeps the raw leading spaces *and* adds a hanging indent, so the gap between bullet and text grows each level. P turns any 4-space-indented item (`    - c`) into a **code block**. |
| Tab-indented / 4-space nested list | ⚠️ | ❌ | P renders both as code blocks. |
| Ordered list start number, `1)` | ✅ | ✅ | |
| List-item continuation / multi-paragraph items | ❌ | ❌ | E doesn't indent continuation lines. P splits them into separate paragraphs outside the list. |
| Fenced code inside a list item | ⚠️ | ⚠️ | Rendered as a top-level block. P keeps the 3-space indent inside the code. |
| Task lists `- [ ]` / `- [x]` | ✅ | ✅ | Glyphs only: **not clickable in either pane**. |
| Ordered task `1. [ ]` | ❌ | ❌ | Rendered as a literal `[ ]`. |
| Blockquote | ⚠️ | ✅ | E styles it as grey italic text with no bar or background. P has an accent bar and tint. |
| `>text` (no space), `  > indented` | ❌ | ⚠️ | E misses both. P misses `>text`. |
| Nested quotes `>>` / `> >` | ❌ | ❌ | Inner markers are shown raw. |
| Lazy continuation | ✅ | ✅ | Both end the quote (spec says continue). |
| Lists / headings inside quotes | ❌ | ❌ | Raw `- ` / `# ` inside the quote text. |
| GitHub alerts `> [!NOTE]` | ⚠️ | ✅ | E shows the literal `[!NOTE]` with no icon. `> [!WARNING] text` on one line is a bold, coloured line. P renders the icon and title correctly. |
| Tables (GFM) | ✅ | ✅ | Interactive grid in E. Inline code in cells isn't monospaced in either pane. Tables re-serialise on any edit (D5). |
| `a \| b` in normal prose | ✅ | ✅ | Renders fine, but the bubble menu treats the line as a table (§6). |
| HTML blocks `<details>` | ❌ | ❌ | Raw tags. |
| Footnote definitions | ⚠️ | ✅ | E is styled but the `[1]:` marker stays as text. |
| Mermaid / math blocks | ❌ | ❌ | Plain code block / raw text. |
| Definition lists | ❌ | ❌ | Not GFM; scope decision. |

---

## 5. Editing behaviour vs Notion

Verified by sending real `insertNewline`, `insertTab`, `deleteBackward`, `moveRight` and `undo` commands to the editor.

| Behaviour | Expected (Notion / Typora / Bear) | Swash today |
| :--- | :--- | :--- |
| Enter at end of `- item` | New `- ` item | Plain new line: `- first item\nsecond` |
| Enter at end of `1. item` | `2. ` | Plain new line |
| Enter at end of `- [x] item` | `- [ ] ` | Plain new line |
| Enter on an empty list item | Exit the list | n/a |
| Enter in a quote | `> ` continues | Plain new line |
| Tab / ⇧Tab in a list | Indent / outdent the item | Inserts a literal tab at the caret: `- b\t` |
| Backspace at the start of heading text | Turns into a paragraph | Deletes the hidden space: `##Title` (becomes literal text) |
| Backspace at the start of list text | Removes the bullet | Deletes the hidden space: `-item` |
| → across `**b**` | 1 press per visible character | 6 presses to cross 3 visible characters (the caret stops on hidden markers) |
| Type after a bold word | Continues outside bold (configurable) | Text goes *inside* the markers: `**boldX**` |
| ⌘B / ⌘I / ⌘K / ⌘E | Toggle format | No Format commands are registered, and `isRichText = false`, so they do nothing (the tooltip still advertises "Bold (⌘B)") |
| Click a checkbox | Toggle `[ ]`/`[x]` | Nothing (the marker is drawn by the layout manager with no hit-testing) |
| Undo a bubble-menu action | Undoes it | `canUndo == false`, so it **can't be undone** |
| Undo typing | Undoes it | ✅ Works (tables are still re-serialised) |
| Paste rich text / HTML | Converts to markdown | Plain text only: formatting and links are dropped |
| Copy | Rich + markdown | ✅ RTF/HTML plus raw-markdown fallback |
| Markdown shortcuts (`# `, `- `, `> `, `` ``` ``) | Convert live | ✅ (implicitly, because styling is live) |
| `/` slash command, block handle, drag to reorder | Yes | Absent |

---

## 6. Bubble menu audit

Each case was exercised through the menu's own action closures in a hosted `ContentView`.

### 6.1 What works
Bold, italic, strike and inline code toggles on plain paragraphs. Heading toggle with "smart" level, plus the H1–H6 dropdown. Quote, bullet and numbered toggles (as "turn into"). Code-block language switching. Link add, edit and remove on a standalone link. Text → table conversion (space- or tab-separated).

### 6.2 Defects
| Case | Result |
| :--- | :--- |
| Any selection after an image, table or long link | Wrong span edited (D1–D3) |
| Toggle italic **off** on `_emph_` | No-op. In `applyFormatting(.italic)` the closing-underscore check reads `fullText[index(upperBound, offsetBy: 1)]`, one character past the underscore, so it falls back to `*` and finds nothing to remove. |
| Double-click word (trailing space selected) → Bold | `**word **then`: invalid emphasis that renders as literal asterisks. Selections need whitespace trimming. |
| Multi-line selection → Bold / Code | `**one\nline**`, `` `one\nline` ``: the editor can't render either. Should apply per line or per block. |
| Inline code → Swift block | `call ```swift\nfoo()\n``` now`: the fence isn't on its own line, so the result is invalid. |
| Bullet on a task item | `[ ] task item`: leaves a literal `[ ]` |
| Numbered on a task item | `1. [ ] task item`: an unsupported construct (§4.2) |
| Bullet in a quote | Replaces `> ` with `- ` (the quote is lost; can't nest a list in a quote) |
| `~~~` code block | Context reports `standard` (only ``` is recognised), so Bold/Italic etc. are offered inside code |
| `1)` ordered list | Context reports `standard`, not `listItem` |
| `> [!NOTE]` alert | Treated as a plain quote; there are no alert-type actions |
| Prose containing ` \| ` | Context becomes `tableCell`. Heading, quote and list buttons disappear and an *active* "Remove Table" button appears, which when clicked **creates** a table from the selection. |
| Unknown language (`rust`) | Shown as "Plain". Choosing any language overwrites `rust`, and only 9 languages are offered. |
| Heading / code dropdowns | Two chevrons are rendered (SwiftUI `Menu` indicator plus the custom chevron), visible in the snapshots. |
| Caret with no selection | No menu (except on links), so there's no way to "turn into" the current block without selecting text. |
| Action applied | `document.text` is replaced wholesale. Undo is lost, and the scroll and typing state is reset. |

### 6.3 Missing actions for a Notion-like menu
Task-list toggle · "Turn into ▸" block menu (Text / H1–H3 / Bullet / Numbered / Todo / Quote / Callout / Code / Divider) · Callout type picker for alerts · Highlight / text colour (decide representation: `==`, `<mark>`) · Inline math · Indent / outdent · Clear formatting · Link to heading (anchor) · Copy as markdown / copy link · Insert divider, table, image · Keyboard shortcuts mirrored in a Format menu · Selection-less block menu (⋮⋮ handle or `/`).

---

## 7. Performance

`highlightMarkdown` timing on a repeating section (heading, paragraph with bold, italic, link and code, a two-item list, and a fenced block):

| Lines | Chars | Restyle per keystroke |
| ---: | ---: | ---: |
| 111 | 1,330 | 14 ms |
| 551 | 6,650 | **429 ms** |
| 2,201 | 26,600 | **26,949 ms** |

The growth is quadratic. `isRangeInCodeBlock` re-scans the whole string for fences per match, and the bare-URL, link, footnote and image passes repeat this. On top of that, the whole document's attributes are reset, and all table SwiftUI subviews are torn down and rebuilt on every keystroke. Any realistic document (a README or design doc) is effectively un-editable in Edit Text mode.

---

## 8. Recommendations

### Phase 0: stop the bleeding (small, isolated fixes)
1. **Offset mapping**: convert selection ranges storage ↔ raw in `Coordinator.updateSelectionRect` and when applying `selectedRange` (fixes D1–D3).
2. **Skip image matches that fall inside a pending table range** (fixes D4).
3. **Preserve original table source** unless that table was edited: store the raw text on `TableTextAttachment` and serialise from it when the attachment is unchanged (fixes D5).
4. **Precompute code ranges once per pass** (fences, indented code, and code spans) and test intersections against that array: O(n) instead of O(n²).
5. Route bubble edits through `textView.shouldChangeText(in:replacementString:)` / `replaceCharacters` / `didChangeText` on the live text view, so they are undoable and don't reset the view.
6. Fix the italic-underscore off-by-one; trim whitespace from selections before wrapping; put code fences on their own lines; recognise `~~~` and `1)` in the context helpers.

### Phase 1: one parser, one model
Replace the four interpretations with **one CommonMark/GFM AST that carries source ranges**. [`swift-markdown`](https://github.com/swiftlang/swift-markdown) (cmark-gfm) is the natural choice: it is first-party, handles all GFM extensions, gives exact `SourceRange`s, and parses incrementally fast enough. Then:
- **Preview** renders from the AST, instead of `MarkdownParser` plus `AttributedString`.
- **Editor** styles text from the AST's ranges. Nesting, escapes, code spans, reference links and autolinks all become correct for free.
- **Bubble context** = "which AST nodes enclose the selection", replacing the line-prefix heuristics.
- **Bubble actions** become AST-aware transforms that emit minimal text edits.
- **Restyle incrementally**: re-parse, diff the changed top-level blocks, and restyle only those ranges.

### Phase 2: Notion-grade editing
- Keyboard: list/quote/task continuation on Enter, exit on an empty item, Tab/⇧Tab indent, Backspace-unformat at block start, ⌘B/⌘I/⌘E/⌘K/⌘⇧X via a Format `CommandMenu`.
- **Caret atomicity**: snap the caret out of hidden marker ranges (`textView(_:willChangeSelectionFromCharacterRange:toCharacterRange:)`). Alternatively, reveal the markers of the span under the caret (Typora/Obsidian live-preview style), which also fixes "type at end of bold".
- Clickable task checkboxes (hit-test the marker rect in `SwashNSTextView.mouseDown`).
- Paste: HTML/RTF → markdown conversion.
- A selection-less block menu (`/` command and/or a gutter handle) with "Turn into".
- A language badge on code blocks (click to change), matching Preview.

### Phase 3: rendering parity and extensions
Nested lists and quotes with correct indentation geometry; multi-paragraph list items; blockquote bar and tint in the editor matching Preview; alert icon and title in the editor; linked images; front matter (collapse into a metadata chip); `<br>`, `<kbd>`, `<sub>`/`<sup>`, `<details>`, and comment hiding; optionally math (KaTeX/MathJax-free native renderer) and Mermaid.

### Testing
- Turn `Tests/EditorAudit/AuditRunner.swift` into **asserting** golden tests (visible text + style runs + exact round-trip) and wire them into `run_spec_tests.sh` and CI.
- Make the existing GFM runner assert editor output, not just "PNG written".
- Add the bubble-action and interaction cases as regression tests (inputs and expected outputs are already listed in §3, §5 and §6).
- Add a performance budget: < 16 ms restyle for a 1,000-line document.
- Stop the spec runner overwriting tracked snapshots in place (write to `build/`, compare against goldens).

---

## Appendix: reproduction harness

| File | What it does |
| :--- | :--- |
| `Tests/EditorAudit/AuditRunner.swift` | Loads 64 markdown probes into the real WYSIWYG editor. Dumps the visible text (hidden markers removed) and style runs, checks round-trip, records the Preview block model, and writes side-by-side PNGs. |
| `Tests/EditorAudit/InteractionRunner.swift` | Sends real editing commands (Enter, Tab, Backspace, arrow keys, undo, paste, copy) and records the resulting markdown. |
| `Tests/EditorAudit/BubbleRunner.swift` | Hosts the real `ContentView`, selects text, captures the bubble menu's context and active state, invokes its action closures, and checks undo. |
| `Tests/EditorAudit/PerfRunner.swift` | Times `highlightMarkdown` across document sizes. |
| `Tests/EditorAudit/run_audit.sh` | Builds and runs any or all of the above into `build/editor-audit/`. |
