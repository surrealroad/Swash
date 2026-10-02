---
"swash": minor
---

Edit Text, the Preview pane, Quick Look and table cells now all render Markdown from one new CommonMark 0.31.2 + GitHub Flavored Markdown parser (`Swash/Markdown/`), so the editor and the preview agree. The parser records the exact source range of every node and syntax marker.

- Supports nested emphasis, backslash escapes, emphasis spanning lines, reference links, `<…>` autolinks, linked images (README badges), nested and multi-paragraph lists, code blocks inside list items, nested blockquotes, ordered task items, GitHub alert titles, footnote references and YAML front matter.
- Bold and inline code inside headings keep the heading size, in both panes.
- The Preview renders soft line breaks as spaces (CommonMark), hides raw inline HTML tags (`<br>` becomes a line break), and shows front matter as a metadata box.
- Styling large documents is faster.
- Slack mrkdwn documents keep their existing styling.
- The parser passes all 652 CommonMark spec examples and all 50 GFM extension examples (`./scripts/run_commonmark_spec.sh`).
