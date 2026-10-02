---
"swash": minor
---

Rendering parity and extensions:

- **Inline HTML** renders in both Edit Text and the Preview:
  - keycaps (`<kbd>`), sub- and superscript (`<sub>` / `<sup>`), highlight (`<mark>`), underline (`<u>`, `<ins>`) and strikethrough (`<s>`, `<del>`);
  - bold, italic, small and code tags.

  Paired tags are hidden in Edit Text like Markdown markers. Inline `<img>` tags show as images and respect their `width`, and `<br>` breaks the line in the Preview.
