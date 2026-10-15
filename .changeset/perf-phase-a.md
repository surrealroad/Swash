---
"swash": patch
---

Performance: typing does less work per keystroke. The editor parses each revision once and shares that parse with styling, link detection, the bubble menu and Backspace/Enter handling, and it skips rebuilding the document when SwiftUI only echoes back its own edit. Tables cache their Markdown. Images are cached by path and modification date instead of being reread and rescaled on every restyle, so typing next to an image is about 4× faster. Backspace in an ordinary paragraph no longer parses the whole document. Saved folder permissions are resolved when first needed, once each, which fixes access handles accumulating with every render. The scroll position is only restored after full restyles, so it no longer fights autoscroll while typing.
