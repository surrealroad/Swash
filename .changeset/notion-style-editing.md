---
"swash": minor
---

Notion-style structural editing in the editor:

- **Enter** continues bullet, numbered (following items are renumbered), to-do and quote lines, and splits an item at the caret. Enter on an empty item outdents a nested item, or leaves the list or quote.
- **Tab / ⇧Tab** nest and un-nest list items under their previous sibling.
- **Backspace** at the start of a heading, list item or to-do removes its marker, and at the start of a quoted line removes one quote level.

- **Caret movement** skips hidden Markdown markers. ← / → move one visible character per press, and clicking at the start of a heading or list item places the caret on its text rather than inside the hidden marker.

Code blocks are never affected, and every change can be undone.
