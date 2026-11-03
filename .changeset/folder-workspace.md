---
"swash": minor
---

Folder windows now work like a notes workspace. The sidebar shows subfolders as a collapsible tree, and a filter field narrows it by file name. Search (⇧⌘F) looks through the text of every note in the folder and lists each match with its line. Choosing a match opens the note with the match selected. Clicking a relative link to another Markdown file, or a `[[wiki link]]` naming a note, opens that note in the same window. You can rename a file or folder, move it to the Trash (after confirming) or show it in Finder from the sidebar's context menu. Hidden folders, `.git`, `node_modules` and build folders are skipped, and very large folders are listed only up to a limit, so they stay fast.
