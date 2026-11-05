# The Markdown engine lives in PixerateMarkdown

Decision for [#50](https://github.com/Pixerate/Swash/issues/50), made on 4 November 2026, with
[Pixerate/editor#546](https://github.com/Pixerate/editor/issues/546).

## Decision

Swash's Markdown engine moves out of `Swash/Markdown/` into **`PixerateMarkdown`**, a library
product of the Pixerate editor's SwiftPM package (`Package.swift` at the root of
[Pixerate/editor](https://github.com/Pixerate/editor), sources in
`packages/swift/Sources/PixerateMarkdown`). Swash depends on it. There is one Swift Markdown
engine, shared by Swash and Pixerate's native editors, held to the same corpus
(`@pixerate/markdown-conformance`) as the web editor.

## What moved and what stayed

| Moved to `PixerateMarkdown` (Foundation only) | Stayed in Swash (AppKit / UIKit / SwiftUI / WebKit) |
| :--- | :--- |
| Parser: `MarkdownBlockParser`, `MarkdownInlineParser`, `MarkdownNode` / `MarkdownDocument`, `MarkdownSyntax`, `MarkdownEntities`, `MarkdownInlineHTML`, `MarkdownMath` | `SwashTextView` (the editing view) and its coordinator |
| `MarkdownHTMLRenderer`, `HTMLToMarkdown` (with `HTMLLiteDOM` for iOS, from #13) | `MarkdownParser.swift` (attribute styling), `MarkdownEditorStyler`, `CodeHighlightTheme` |
| `CodeHighlighter`, `MarkdownOutline` / `MarkdownStatistics` | `MarkdownPreviewView`, `RichContentRenderer` (KaTeX, Mermaid), `BubbleMenuView` |
| `MarkdownFormatting`, `MarkdownEditingCommands`, `MarkdownMathEditing` | `FormatCommands.swift` (key events, the Format menu, `FocusedValues`) |
| `FormatCommand`, `FormatCommandEdits`, `FormatManifest` (generated from the corpus manifest in the editor repo) | `MarkdownFlavor`, documents, folders, export, settings |

`SwashTextView` is not shared. It is Swash's product surface, written against NSTextView, and
Pixerate's rich text will be a different model (TipTap documents on TextKit 2, #546 step 3). What
Pixerate needs from Swash is the model and the commands.

## Why

- **One engine, not three.** Without this, Pixerate would write a second Swift Markdown engine
  next to Swash's and the TypeScript one. Each change to Markdown behaviour would then be made and
  tested three times.
- **The line was already clean.** Every file in `Swash/Markdown/` imported only Foundation, and the
  `swiftc` test scripts already compiled it on its own.
- **The corpus and manifest live with the engine.** The format-command manifest is generated in
  the repo that owns it, so Swash no longer installs `@pixerate/markdown-conformance` from npm or
  runs a generator.

## Consequences

- **Xcode build.** The project has a remote package reference to
  `https://github.com/Pixerate/editor`, **up to next minor** from `0.9.0`, the first release with it:
  `@pixerate/swift` is 0.x, and a 0.x minor may break. `Package.resolved` is committed. SwiftPM
  clones the editor repo (about 85 MB of history) once, but builds only the `PixerateMarkdown`
  target. Its minimum platforms (macOS 14, iOS 17) are below Swash's.
- **Release cadence.** An engine change is made in the editor repo, released there (the release
  workflow tags `v<version>` when `@pixerate/swift` changes), and then taken by Swash with a pin
  bump. Swash still releases on its own schedule. A fix that has to ship in Swash first is made in
  both, in that order.
- **Extensions.** Quick Look compiles the app's sources, so it links the product too. Share,
  Thumbnail and Widget don't use the engine. The library is a static, Foundation-only module, so
  it adds no entitlements and changes nothing about sandboxing.
- **Tests.** The engine's own tests (CommonMark 0.31.2 and GFM examples, parser and highlighter
  checks, the editing corpus) run in the editor repo's Swift CI on macOS and in the iOS simulator.
  Swash's scripts still run them, against the pinned revision: `scripts/pixerate_markdown.sh`
  fetches the engine, its checks and the corpus into `build/pixerate-editor` and builds the module
  with `swiftc`. Set `PIXERATE_EDITOR_DIR` to try a local checkout. See GOTCHAS #63.
- **Universal app (#13).** It adds `HTMLLiteDOM` and an iOS build; the engine side of that
  (`HTMLLiteDOM`, the converter switch) is now in the package and builds for iOS, so #13 drops its
  copies when it is rebased. Three engine additions from #13 aren't in the package yet: Confluence and
  Jira image pastes (`HTMLToMarkdown.convert(_:sourceURL:)`), `FormatCommandEdits.activeLink` and
  `MarkdownSyntax.url`. They sit in `Swash/PixerateMarkdownExtensions.swift` on top of the public API,
  with checks in `scripts/run_paste_tests.sh`, until they move upstream.

## Alternatives considered

- **A library product in this repo, with Pixerate depending on Swash.** Rejected: Pixerate's Swift
  package is the home of the shared contracts, generators and conformance runners, and its editors
  must not depend on an app repository.
- **Keep two engines and share only the corpus.** Rejected: the corpus catches differences, but
  every behaviour would still be written twice.
