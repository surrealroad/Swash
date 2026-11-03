---
"swash": minor
---

Adopt the shared `@pixerate/markdown-conformance` package. The Format menu, keyboard shortcuts, bubble menu labels and code-block languages now come from its format-command manifest (generated into `FormatManifest.generated.swift`), and its editing corpus runs against Swash in `scripts/run_conformance_tests.sh` and the PR build.

Editing fixes found by the corpus:
- Leaving a list or quote with Return on an empty item now adds a blank line, so the next paragraph no longer joins the list.
- Tab on a list item that can't be nested no longer inserts a tab character.
- Nesting a numbered item starts the nested list at 1, and moving it back out renumbers it after its parent.
- Adding, editing or removing a link keeps the selection on the link text.
- Format ▸ Code Block (⌥⌘C) on a caret wraps the whole line and keeps the caret; inside a code block it removes the fences. Formatting commands that don't apply inside code (bold, italic, strikethrough) do nothing there.
