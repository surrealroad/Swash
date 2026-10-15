---
"swash": patch
---

Performance: formulas waiting to render are typeset together and captured in one snapshot (up to 16 at a time) instead of one snapshot each, so documents with a lot of math show their formulas sooner.
