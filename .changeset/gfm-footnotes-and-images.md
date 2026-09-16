---
"swash": minor
---

Support GitHub Flavored Markdown (GFM) footnotes and images across the block parser, Formatted mode editor, preview pane, and Quick Look plugin.

- **Footnotes**:
  - Parsed multi-line continuation footnote definitions and inline references `[^label]`.
  - Hoisted footnote definition blocks to the bottom of the document in Preview and Quick Look with visual separator, anchor targets, and return links `↩`.
  - Styled footnote definitions and references with hanging indents and subtle muted typography in Formatted mode.
- **Images**:
  - Implemented `ImageTextAttachment` with reverse markdown serialization in Formatted editor mode (`NSTextView`).
  - Added strict document-relative and local path resolution without recursive directory scanning.
  - Implemented aspect ratio scaling, tooltip alt/title display, and placeholder badges for missing or remote resources.
  - Added full GFM spec test suites and automated snapshot rendering for footnotes and images.
