---
"swash": minor
---

Fix editor issues in the shipping version and add missing controls:

- The cursor is an arrow over the bubble menu and the editor margins.
- Clicking an image in the Formatted view selects it and shows an image bubble menu: alt text, size presets (written as `<img width>`), Replace…, Show in Finder and Copy Path.
- The View menu lists Formatted (⌘1), Source (⌘2) and Split (⌘3).
- Callouts get their own bubble menu context with a type menu (Note, Tip, Important, Warning, Caution, Plain Quote, Remove Callout), plus a Format ▸ Callout submenu. Removing the quote from a callout no longer leaves `[!NOTE]` behind.
- Callouts and quotes in the Split preview draw their bar the full height of the box, and the preview re-measures when the divider moves.
- Clicking into a table cell clears the editor's text selection, no longer shifts the table, and is faster (measured table height, cached cell parses, fewer notifications, tables kept while typing after them).
- To-do items in the Formatted view use native macOS checkboxes.
- Footnotes: Format ▸ Insert Footnote, a "/" menu item and a bubble menu button add a numbered footnote; clicking a reference jumps to its definition and back; the bubble menu can jump to or delete a footnote.
