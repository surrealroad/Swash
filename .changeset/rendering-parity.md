---
"swash": minor
---

Rendering parity and extensions:

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
