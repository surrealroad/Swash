---
"swash": patch
---

Performance: the Split view preview no longer rebuilds and re-measures the whole document on every keystroke. It updates once typing pauses, and only the blocks that changed are re-rendered, which uses about 4.5× less CPU while typing on a 900-line document.
