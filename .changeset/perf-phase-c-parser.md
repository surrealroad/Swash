---
"swash": patch
---

Performance: the Markdown parser is about 20% faster on ordinary documents, and inputs that used to take time proportional to the square of their length (long runs of unmatched `*`, `_`, `&` or `<`, many `[` before links, long lists of reference definitions, deeply nested quotes) now parse in linear time. Checking block formats on a long selection is about 40× faster.
