---
"swash": minor
---

Achieve full feature parity with GitHub Flavored Markdown (GFM) Specification:
- Parser: Add support for link reference definitions, arbitrary fence lengths (backticks and tildes), ATX closing hashes, Setext headings, thematic breaks with mixed characters/spaces, list marker variations (`-`, `*`, `+`, numbered), and pipe handling inside code spans in tables.
- Formatted Editor: Render continuous alert callout blocks, Setext headings with hidden delimiter lines, thematic break divider rules, interactive checkbox markers with custom tint, and expanded underscore-based inline emphasis.
- Preview & Quick Look: Add base URL resolution for document-relative assets and hide link reference definition blocks.
- Test Suite: Add comprehensive GFM compliance fixture suite and headless snapshot renderer covering 40 spec cases across 7 categories.
