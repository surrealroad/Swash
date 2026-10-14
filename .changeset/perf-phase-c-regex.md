---
"swash": patch
---

Performance: tables, HTML blocks, link definitions and image titles are parsed without compiling a regular expression each time, and detecting a document's Markdown flavor when it opens examines only its first 32 KB, with patterns compiled once.
