---
"swash": patch
---

Fix WYSIWYG "Edit Text" data-corruption and performance bugs (audit Phase 0):

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
