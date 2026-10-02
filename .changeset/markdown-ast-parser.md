---
"swash": minor
---

Edit Text now renders Markdown from a new CommonMark 0.31.2 + GitHub Flavored Markdown parser (`Swash/Markdown/`), which records the exact source range of every node and syntax marker.

- Supports nested emphasis, backslash escapes, emphasis spanning lines, reference links, `<…>` autolinks, linked images (README badges), nested and multi-paragraph lists, code blocks inside list items, nested blockquotes, ordered task items, GitHub alert titles, footnote references and YAML front matter.
- Bold and inline code inside headings keep the heading size.
- Styling large documents is faster.
- Slack mrkdwn documents keep their existing styling.
- The parser passes all 652 CommonMark spec examples and all 50 GFM extension examples (`./scripts/run_commonmark_spec.sh`).
