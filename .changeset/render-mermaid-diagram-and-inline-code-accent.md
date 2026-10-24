---
"swash": minor
---

Render Mermaid diagrams as inline image attachments and use system accent color for inline code:

- Formatted view collapses Mermaid fenced code blocks into an interactive image attachment showing the rendered diagram (or placeholder while rendering) rather than displaying source code text and fences beneath it.
- Selecting, cutting, copying, or deleting the diagram operates like inline images, preserving the raw Markdown when copied or edited.
- Raw mode (Source view) retains direct plain text editing of Mermaid code blocks.
- Inline code text in formatted mode and preview view now uses the system accent color (`NSColor.controlAccentColor` / `Color.accentColor`) instead of hardcoded purple.
