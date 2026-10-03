# swash

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
