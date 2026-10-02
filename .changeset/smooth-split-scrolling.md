---
"swash": patch
---

Make scrolling in split view smooth. The editor and preview now stay in step without re-parsing and re-laying out the whole preview on every scroll frame, and the preview reuses its parse when the text has not changed.
