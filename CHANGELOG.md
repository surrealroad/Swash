# swash

## 1.15.0

### Minor Changes

- 007c708: Add images by dragging them onto a document or pasting them, including screenshots. Swash copies the image into an `assets` folder beside the document and inserts a relative `![](assets/…)` link; images already in the document's folder are linked where they are. The folder can be changed (or left empty to use the document's own folder) in Settings › General › Images. If Swash doesn't have permission to write to the folder, it asks for access first. An untitled document has to be saved before a screenshot can be pasted into it.
- a4d06c7: Export and print documents. File › Export as PDF… and Export as HTML… save the document as it looks in the Preview, with math, Mermaid diagrams, alerts, footnotes and images included. HTML exports are a single self-contained file. File › Print… (⌘P) prints it, and Edit › Copy as Rich Text and Copy as HTML put the whole document on the clipboard for Mail, Pages or Google Docs.
- 52f24eb: New writing modes in the View menu on the Mac. Focus Mode (⇧⌘D) dims everything except the paragraph or sentence you're writing (choose which under Focus On). Typewriter Scrolling (⌃⌘T) keeps the line you're typing in the middle of the window. Distraction-Free Writing (⌃⇧⌘F) goes full screen, hides the toolbar, outline and status bar, and centres the text in a readable column; press Esc to leave it.

### Patch Changes

- db72882: Showing or hiding the outline sidebar now widens or narrows the window by the sidebar's width, so the document keeps its width and stays in place, as it already does when switching to and from Split view.
- cf772aa: The README's screenshot now shows Swash in Light or Dark Mode to match the reader's system, with the outline, a callout, a table, math and a Mermaid diagram, and the feature list covers exporting, printing, writing modes and adding images.

## 1.14.5

### Patch Changes

- d1ca2b6: Rewrite the README for people using Swash rather than building it: it now leads with what Swash does, lists its current features and keyboard shortcuts, explains how to install it, and previews the iPhone and iPad app. Release and code-signing notes moved to `docs/RELEASING.md`.

## 1.14.4

### Patch Changes

- f3af456: Restore the original thin line thickness for horizontal dividers (thematic breaks) in the formatted editor.

## 1.14.3

### Patch Changes

- c166ff3: Fix vertical alignment of checkboxes, bullet/numbered list markers, and alert callout icons to align accurately with the text baseline and cap height.

## 1.14.2

### Patch Changes

- 4e4c975: Improve vertical rhythm and text spacing in formatted editor mode:
  - Add generous paragraph spacing before and after headings
  - Increase line spacing and paragraph spacing for body text and list items
  - Reduce contrast and add balanced padding for horizontal rules (thematic breaks)
  - Refine block quote, alert callout, and code block vertical margins
  - Update GFM editor snapshot baselines

## 1.14.1

### Patch Changes

- 4c92adb: Increase text line height and reduce divider contrast in preview mode for a more comfortable and elegant reading rhythm.

## 1.14.0

### Minor Changes

- fe835ff: Render Mermaid diagrams as inline image attachments and use system accent color for inline code:
  
  - Formatted view collapses Mermaid fenced code blocks into an interactive image attachment showing the rendered diagram (or placeholder while rendering) rather than displaying source code text and fences beneath it.
  - Selecting, cutting, copying, or deleting the diagram operates like inline images, preserving the raw Markdown when copied or edited.
  - Raw mode (Source view) retains direct plain text editing of Mermaid code blocks.
  - Inline code text in formatted mode and preview view now uses the system accent color (`NSColor.controlAccentColor` / `Color.accentColor`) instead of hardcoded purple.

## 1.13.0

### Minor Changes

- ae37e74: Fix editor issues in the shipping version and add missing controls:
  
  - The cursor is an arrow over the bubble menu and the editor margins.
  - Clicking an image in the Formatted view selects it and shows an image bubble menu: alt text, size presets (written as `<img width>`), Replace…, Show in Finder and Copy Path.
  - The View menu lists Formatted (⌘1), Source (⌘2) and Split (⌘3).
  - Callouts get their own bubble menu context with a type menu (Note, Tip, Important, Warning, Caution, Plain Quote, Remove Callout), plus a Format ▸ Callout submenu. Removing the quote from a callout no longer leaves `[!NOTE]` behind.
  - Callouts and quotes in the Split preview draw their bar the full height of the box, and the preview re-measures when the divider moves.
  - Clicking into a table cell clears the editor's text selection, no longer shifts the table, and is faster (measured table height, cached cell parses, fewer notifications, tables kept while typing after them).
  - To-do items in the Formatted view use native macOS checkboxes.
  - Footnotes: Format ▸ Insert Footnote, a "/" menu item and a bubble menu button add a numbered footnote; clicking a reference jumps to its definition and back; the bubble menu can jump to or delete a footnote.

## 1.12.1

### Patch Changes

- 909c90f: Align app icon squircle to standard macOS Human Interface Guidelines (824×824 px on 1024×1024 grid) with subtle drop shadow

## 1.12.0

### Minor Changes

- 93b031e: Math editing: inside `$…$`, `$$` blocks and math code blocks, typing `{` inserts a matching `}` (wrapping any selection), and typing `}` steps over an existing one. After a backslash, the system completion shortcut (Esc or ⌥Esc) lists KaTeX commands such as `\frac`, `\alpha` and `\rightarrow`.
- 93b031e: Translate: the formatting bubble has a Translate button for selected text. It opens the system translation popover, and Replace puts the translation into the document as a single undoable edit. Markdown syntax in the selection isn't sent for translation, and formatting within the replaced text isn't kept.

### Patch Changes

- 93b031e: Performance: formulas waiting to render are typeset together and captured in one snapshot (up to 16 at a time) instead of one snapshot each, so documents with a lot of math show their formulas sooner.
- 93b031e: Performance: the formatting bubble finds code blocks and code spans once per document change, instead of rescanning the document several times each time it updates.
- 93b031e: Performance: while you type, Swash no longer looks for a link under the caret after every keystroke. That check scanned the whole document and was the main cost of typing in Source and Slack modes. The bubble menu for a link now appears once typing pauses.

## 1.11.0

### Minor Changes

- 6b144c8: Editor: the system find bar (⌘F, with incremental search) is now enabled. Writing Tools leaves code, math, HTML, front matter, tables and images untouched, and Swash holds off restyling and saving until a rewrite finishes. VoiceOver gets Headings, Links and Tables rotors for moving around a document.
- 6b144c8: Outline and statistics: a heading outline sidebar (View ▸ Show Outline, ⌃⌘S) follows the caret and jumps to a heading when you click it. The status bar now counts only the text readers see. Click the count to switch between words, characters, characters without spaces, paragraphs and reading time; with text selected it shows "selected of total". Format ▸ Insert Table of Contents adds a linked list of headings. The Edit menu gains Copy Heading Link (⌃⌘C), Copy as Markdown Link and Copy File Path.
- 6b144c8: Quick Note, importing and safer opening:
  
  - **Quick Note:** a floating panel opened with a global shortcut (⌃⌥⌘N by default, changeable in Settings), an optional menu bar item, or the Quick Note shortcut. It saves a note as a new document or appends it to the last document you used. Settings can also turn on Open at Login.
  - **Import:** File ▸ Import… (⇧⌘I) converts Word, RTF, HTML and OpenDocument files into new Markdown documents.
  - **Reopen:** File ▸ Reopen Closed Document (⇧⌘T) brings back recently closed files.
  - **Opening files:** requests are gathered together, and Swash asks before opening more than ten at once. A file that can't be opened gets a specific reason: missing, a folder, no permission, too large, or not text.
  - **File types:** `.mkd`, `.mdwn`, `.mdtext`, `.mdtxt` and `.rmd` now open as Markdown, and UTF-16 and legacy-encoded files are decoded instead of rejected.
  - **iCloud conflicts:** a banner offers to choose which conflicting version to keep, and keeping another version can be undone.

## 1.10.3

### Patch Changes

- 1f0b69a: Performance: typing does less work per keystroke. The editor parses each revision once and shares that parse with styling, link detection, the bubble menu and Backspace/Enter handling, and it skips rebuilding the document when SwiftUI only echoes back its own edit. Tables cache their Markdown. Images are cached by path and modification date instead of being reread and rescaled on every restyle, so typing next to an image is about 4× faster. Backspace in an ordinary paragraph no longer parses the whole document. Saved folder permissions are resolved when first needed, once each, which fixes access handles accumulating with every render. The scroll position is only restored after full restyles, so it no longer fights autoscroll while typing.
- 1f0b69a: Performance: an unsaved window no longer looks up its document on every update.
- 1f0b69a: Performance: the window no longer checks the folder permissions of every linked image on every keystroke (it rechecks once typing pauses, and straight away when the file moves or access is granted), the share icon is drawn once, and finding the document's title stops at its first heading.
- 1f0b69a: Performance: the Split view preview no longer rebuilds and re-measures the whole document on every keystroke. It updates once typing pauses, and only the blocks that changed are re-rendered, which uses about 4.5× less CPU while typing on a 900-line document.
- 1f0b69a: Performance: Quick Look previews read at most the first 256 KB of a file, noting when a preview is cut short, and decode and parse it in the background. They show math and Mermaid source instead of starting WebKit, so the Quick Look extension no longer bundles KaTeX, Mermaid and their fonts (about 6 MB). Finder thumbnails read only the first 4 KB of a file.
- 1f0b69a: Performance: typing inside a formula or Mermaid diagram no longer queues a render of every intermediate state, since each block's newest request replaces its older queued one. Renders for views that have gone away are dropped, and finished renders are announced in batches rather than one at a time, so opening a document with many formulas restyles it a few times instead of once per formula.
- 1f0b69a: Performance: scrolling no longer looks up links or recomputes the selection on every frame; it just moves the bubble menu. In Source and Split modes, typing no longer restyles the whole document on every keystroke.
- 1f0b69a: Performance: Slack-formatted documents are restyled once typing pauses (after about 0.1 s) instead of after every keystroke, since Slack styling always covers the whole document.
- 1f0b69a: Performance: editing a table cell no longer makes the next keystroke restyle the whole document, rebuild every table and reload every image.
- 1f0b69a: Add a performance audit (`docs/PERFORMANCE_AUDIT.md`) covering per-keystroke editor work, the preview, image loading, the Markdown parser, math and Mermaid rendering, and the extensions, with a phased improvement plan.

## 1.10.2

### Patch Changes

- 24168d9: Performance: finding code blocks and code spans, which the editor does on styling passes, is about 20% faster.
- 24168d9: Performance: the Markdown parser is about 20% faster on ordinary documents, and inputs that used to take time proportional to the square of their length (long runs of unmatched `*`, `_`, `&` or `<`, many `[` before links, long lists of reference definitions, deeply nested quotes) now parse in linear time. Checking block formats on a long selection is about 40× faster.
- 24168d9: Performance: tables, HTML blocks, link definitions and image titles are parsed without compiling a regular expression each time, and detecting a document's Markdown flavor when it opens examines only its first 32 KB, with patterns compiled once.

## 1.10.1

### Patch Changes

- 85ea2e0: Remove the "Metadata extraction skipped" build warnings from the QuickLook, Share and Thumbnail extensions by skipping App Intents metadata extraction for targets that don't use App Intents.

## 1.10.0

### Minor Changes

- 0fadaf6: Move Markdown flavor switching from the toolbar dropdown to Format ▸ Markdown Flavor. When switching changes the text, Swash asks whether to keep the formatting (rewriting the Markdown for the new flavor) or keep the raw text unchanged. Switching flavor, including the rewrite, can be undone with Edit ▸ Undo.

## 1.9.0

### Minor Changes

- 9afcba8: Redesign the Settings window in the modern macOS style. It now has General and Updates tabs in the toolbar, and each tab uses grouped form sections with explanatory footers. The Updates tab also shows the current version.

## 1.8.6

### Patch Changes

- 4f04726: Publish releases with an up-to-date GitHub release action, removing the last warning from release builds. The app itself is unchanged.

## 1.8.5

### Patch Changes

- 28ccd83: Clear the warnings from release builds. The Quick Look, Thumbnail, Share and Widget extensions now report the same version number as the app, deprecated APIs have been replaced, and CI now builds with a toolchain that supports Swash's macOS 15.7 minimum.

## 1.8.4

### Patch Changes

- 10ec240: Make the window toolbar match Finder and other system apps. The Source, Formatted and Split buttons are now a single segmented control that marks the current view with a gray highlight instead of a solid blue fill, and the title now sits in the same row as the toolbar, which uses the standard larger controls.

## 1.8.3

### Patch Changes

- b4b1493: Keep scrolling the preview when a scroll starts over a table or code block. Vertical scrolls now move the page instead of getting stuck on the block, while sideways scrolls still pan wide tables and code.

## 1.8.2

### Patch Changes

- 5ac4735: Make scrolling in split view smooth. The editor and preview now stay in step without re-parsing and re-laying out the whole preview on every scroll frame, and the preview reuses its parse when the text has not changed.

## 1.8.1

### Patch Changes

- d2421b9: Inline math in Preview headings now renders at the heading's size instead of body size.

## 1.8.0

### Minor Changes

- 55708a3: Render math and Mermaid diagrams offline with bundled KaTeX and Mermaid. In the Preview and Quick Look, `$$` blocks, inline `$…$` math and ```` ```mermaid ```` code blocks are typeset or drawn as images. Edit Text shows the rendering under the editable source, keeps the last good result while you type, and shows KaTeX or Mermaid errors inline.

## 1.7.0

### Minor Changes

- 67bc3d2: Rendering parity and extensions:
  
  - **Inline HTML** renders in both Edit Text and the Preview:
    - keycaps (`<kbd>`), sub- and superscript (`<sub>` / `<sup>`), highlight (`<mark>`), underline (`<u>`, `<ins>`) and strikethrough (`<s>`, `<del>`);
    - bold, italic, small and code tags.
  
    Paired tags are hidden in Edit Text like Markdown markers. Inline `<img>` tags show as images and respect their `width`, and `<br>` breaks the line in the Preview.
  - **HTML blocks in the Preview**:
    - `<details>` / `<summary>` render as a collapsible disclosure with the Markdown inside it.
    - Image-only HTML (README badges, centred screenshots) renders the images at their `width`, wrapping in rows.
    - Other HTML blocks are converted to Markdown and rendered.
    - Bare wrapper tags and HTML comments are no longer shown as raw text.
  - **Math**: `$…$` inline math and `$$` display-math blocks are recognised, so formulas are no longer mangled by Markdown formatting. A `$` before a digit ("$5 and $10") stays plain text. Edit Text shows the TeX source in a math style with a MATH badge on display blocks, and the Preview shows a readable Unicode rendering (Greek letters, sub- and superscripts, fractions, roots, operators and arrows).
  - **Alerts in Edit Text** show their icon beside the title, as in the Preview.
  - **Code block badges** no longer overlap long first lines of code.
  - **Faster typing in long documents**: Edit Text now restyles only the blocks an edit changes, instead of the whole document. Keystrokes in a 2,250-line document with tables and images take about 20 ms, down from about 70 ms.

## 1.6.0

### Minor Changes

- dd0df18: Notion-style structural editing in the editor:
  
  - **Enter** continues bullet, numbered (following items are renumbered), to-do and quote lines, and splits an item at the caret. Enter on an empty item outdents a nested item, or leaves the list or quote.
  - **Tab / ⇧Tab** nest and un-nest list items under their previous sibling.
  - **Backspace** at the start of a heading, list item or to-do removes its marker, and at the start of a quoted line removes one quote level.
  
  - **Caret movement** skips hidden Markdown markers. ← / → move one visible character per press, and clicking at the start of a heading or list item places the caret on its text rather than inside the hidden marker.
  
  - **Keyboard shortcuts and a new Format menu**:
  
    | Shortcut | Action |
    | --- | --- |
    | ⌘B / ⌘I / ⌘E | Bold / italic / inline code |
    | ⌘⇧X | Strikethrough |
    | ⌘K | Add, edit or remove a link |
    | ⌥⌘1–3 / ⌥⌘0 | Heading 1–3 / paragraph |
    | ⇧⌘8 / ⇧⌘7 / ⇧⌘9 | Bullet / numbered / to-do list |
    | ⇧⌘. | Quote |
    | ⌥⌘C | Code block |
  
    Shortcuts also work with only a caret.
  
  - **Clickable to-do checkboxes**: clicking a checkbox in Edit Text checks or unchecks the item.
  
  - **Rich paste**: in Edit Text, text pasted from web pages, Google Docs, Pages, Word or TextEdit is converted to Markdown, keeping bold, italic, strikethrough, code, links, images, headings, lists, to-dos, quotes, code blocks and tables. Text copied from code editors keeps its indentation, and Paste and Match Style still pastes plain text.
  - **Copy and paste between Swash documents** is exact, tables and images included.
  
  - **"/" block menu**: typing `/` at the start of an empty line or list item in Edit Text opens a menu that inserts a block:
    - text or Heading 1–3;
    - bulleted, numbered or to-do list;
    - quote or callout;
    - code block, divider or table.
  
  - **Code block language badge**: fenced code blocks in Edit Text show their language in the top-right corner. Click the badge to choose another language.
  
  Code blocks are never affected, and every change can be undone.

## 1.5.0

### Minor Changes

- e688b5f: Edit Text, the Preview pane, Quick Look and table cells now all render Markdown from one new CommonMark 0.31.2 + GitHub Flavored Markdown parser (`Swash/Markdown/`), so the editor and the preview agree. The parser records the exact source range of every node and syntax marker.
  
  - Supports nested emphasis, backslash escapes, emphasis spanning lines, reference links, `<…>` autolinks, linked images (README badges), nested and multi-paragraph lists, code blocks inside list items, nested blockquotes, ordered task items, GitHub alert titles, footnote references and YAML front matter.
  - Bold and inline code inside headings keep the heading size, in both panes.
  - The Preview renders soft line breaks as spaces (CommonMark), hides raw inline HTML tags (`<br>` becomes a line break), and shows front matter as a metadata box.
  - Styling large documents is faster.
  - The bubble menu works from the same parse:
    - Removing bold, italic, strikethrough or code deletes exactly that span's markers, even when the caret is inside it or the span is nested.
    - Formatting across an existing span merges into it instead of producing broken markers.
    - Lists and headings inside quotes stay quoted (`> - item`), and quoting a heading keeps it a heading.
    - Reference links, autolinks and nested formatting inside links are detected, edited and removed correctly.
    - Context detection understands lists inside quotes, headings inside quotes and alerts.
  - Slack mrkdwn documents keep their existing styling and bubble-menu behaviour.
  - The parser passes all 652 CommonMark spec examples and all 50 GFM extension examples (`./scripts/run_commonmark_spec.sh`).

### Patch Changes

- a92b58b: Fix the release build on the CI toolchain (macOS 15.2 SDK). The editor no longer overrides `NSTextBlock.drawBackground`, whose signature differs between SDKs; indented code, quote and alert backgrounds are now painted by the layout manager. Pull requests now run an app build on the release toolchain.

## 1.4.2

### Patch Changes

- 8149498: Add a WYSIWYG "Edit Text" mode audit and gap analysis (`docs/WYSIWYG_AUDIT.md`) with a reproducible editor/bubble-menu/performance probe harness (`Tests/EditorAudit/`), and document new testing gotchas.
- 7c357b0: Fix WYSIWYG "Edit Text" data-corruption and performance bugs (audit Phase 0):
  
  - Bubble-menu actions no longer edit the wrong text when an image, table or link appears earlier in the document. Editor selections are now mapped between text-storage and raw-markdown offsets.
  - Bubble-menu actions are applied as minimal edits on the text view, so they can be undone with ⌘Z.
  - An image inside a table cell no longer deletes text after the table.
  - Untouched tables keep their original markdown instead of being re-formatted on every keystroke.
  - Styling is ~500× faster on large documents: code regions are located once per pass instead of once per match.
  - Code spans of any backtick length and indented code blocks render correctly, and their contents are no longer interpreted as markdown.
  - Bubble menu:
    - recognises `~~~` code blocks, `1)` ordered lists and task items;
    - no longer treats prose containing `|` as a table;
    - fixes toggling `_italic_` off;
    - trims whitespace from selections before wrapping;
    - formats multi-line selections per line;
    - places code fences on their own lines;
    - removes duplicate dropdown chevrons.

## 1.4.1

### Patch Changes

- fd4b48d: Add specialized Antigravity workspace skills for build/test workflows, changeset management, headless snapshots, and App Sandbox handling. Deduplicate repository agent guidelines.

## 1.4.0

### Minor Changes

- 3dacd09: Re-enable macOS App Sandbox with runtime folder permission prompts and persistent security-scoped bookmarks for document assets.

## 1.3.3

### Patch Changes

- 67e1f8b: Fix relative inline image preview in formatted editor by disabling App Sandbox on the main Swash target to permit reading sibling directory assets

## 1.3.2

### Patch Changes

- c194542: Fix inline image preview resolution in formatted editor by tracking baseURL updates and window lifecycle representedURL fallbacks

## 1.3.1

### Patch Changes

- d2a5ccd: Improve headless test snapshot renderer to capture full height of AppKit NSTextView attachments and content

## 1.3.0

### Minor Changes

- eaae2a8: Support GitHub Flavored Markdown (GFM) footnotes and images across the block parser, Formatted mode editor, preview pane, and Quick Look plugin.
  
  - **Footnotes**:
    - Parsed multi-line continuation footnote definitions and inline references `[^label]`.
    - Hoisted footnote definition blocks to the bottom of the document in Preview and Quick Look with visual separator, anchor targets, and return links `↩`.
    - Styled footnote definitions and references with hanging indents and subtle muted typography in Formatted mode.
  - **Images**:
    - Implemented `ImageTextAttachment` with reverse markdown serialization in Formatted editor mode (`NSTextView`).
    - Added strict document-relative and local path resolution without recursive directory scanning.
    - Implemented aspect ratio scaling, tooltip alt/title display, and placeholder badges for missing or remote resources.
    - Added full GFM spec test suites and automated snapshot rendering for footnotes and images.

## 1.2.1

### Patch Changes

- cfdbf0a: docs: update sample preview to showcase task lists and thematic breaks

## 1.2.0

### Minor Changes

- 9dadde2: Achieve full feature parity with GitHub Flavored Markdown (GFM) Specification:
  - Parser: Add support for link reference definitions, arbitrary fence lengths (backticks and tildes), ATX closing hashes, Setext headings, thematic breaks with mixed characters/spaces, list marker variations (`-`, `*`, `+`, numbered), and pipe handling inside code spans in tables.
  - Formatted Editor: Render continuous alert callout blocks, Setext headings with hidden delimiter lines, thematic break divider rules, interactive checkbox markers with custom tint, and expanded underscore-based inline emphasis.
  - Preview & Quick Look: Add base URL resolution for document-relative assets and hide link reference definition blocks.
  - Test Suite: Add comprehensive GFM compliance fixture suite and headless snapshot renderer covering 40 spec cases across 7 categories.

## 1.1.3

### Patch Changes

- a7be6b4: Add automated GFM spec compliance testing and headless visual snapshot test harness for Tables and Task Lists.

## 1.1.2

### Patch Changes

- b5be2cf: Update AGENTS.md to mandate maintaining and checking GOTCHAS.md for issues, pitfalls, solutions, and workarounds.

## 1.1.1

### Patch Changes

- e346b21: Refine release workflow sequence to commit and push version bumps and assets prior to creating GitHub releases.

## 1.1.0

### Minor Changes

- d1de8bb: Mandate and configure Changesets for versioning and change tracking across the repository.
