---
"swash": minor
---

Notion-style structural editing in the editor:

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
