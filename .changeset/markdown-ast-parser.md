---
"swash": minor
---

Add a new CommonMark 0.31.2 + GitHub Flavored Markdown parser (`Swash/Markdown/`) that records the exact source range of every node and syntax marker. It is the foundation for making the Edit Text editor, the preview and the bubble menu share one interpretation of Markdown. It supports tables, strikethrough, task lists (including ordered task items), extended autolinks, footnotes, GitHub alerts and YAML front matter. It passes all 652 CommonMark spec examples and all 50 GFM extension examples (`./scripts/run_commonmark_spec.sh`).
