---
"swash": patch
---

Performance: Quick Look previews read at most the first 256 KB of a file, noting when a preview is cut short, and decode and parse it in the background. They show math and Mermaid source instead of starting WebKit, so the Quick Look extension no longer bundles KaTeX, Mermaid and their fonts (about 6 MB). Finder thumbnails read only the first 4 KB of a file.
