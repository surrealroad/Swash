---
"swash": patch
---

Performance: typing inside a formula or Mermaid diagram no longer queues a render of every intermediate state, since each block's newest request replaces its older queued one. Renders for views that have gone away are dropped, and finished renders are announced in batches rather than one at a time, so opening a document with many formulas restyles it a few times instead of once per formula.
