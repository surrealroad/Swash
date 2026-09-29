---
name: macos-sandbox-bookmarks
description: >-
  Manage App Sandbox restrictions, security-scoped bookmarks, and sibling file access permissions.
  Use when modifying document asset loading, relative image resolution, or sandbox entitlements in Swash.
---

# macOS App Sandbox & Security-Scoped Bookmarks

This skill details how Swash navigates macOS App Sandbox restrictions to load sibling document assets (e.g., local images referenced in Markdown files).

## 1. Sandbox Architecture & The Sibling Asset Problem

When `ENABLE_APP_SANDBOX = YES`:
- macOS Powerbox only grants the app process security access to the exact user-selected Markdown file.
- Sibling files (e.g. `![Screenshot](Screenshot.png)` located in the same directory) are denied access at the kernel level (`isReadableFile` returns `false`, `NSImage(contentsOfFile:)` fails).

## 2. Solution & Entitlements

Swash resolves this by prompting the user for directory access and saving a persistent security-scoped bookmark.

### Required Entitlements
Ensure the following entitlements are configured on the main `Swash` target:
- `com.apple.security.files.user-selected.read-write`
- `com.apple.security.files.bookmarks.app-scope`

### Runtime Flow (`FolderAccessManager.swift`)
1. **Detection**: `MarkdownPreviewView` detects unreadable relative assets when parsing markdown.
2. **Access Prompt**: An access banner appears with a "Grant Access…" button (also accessible via `File -> Grant Folder Access…`).
3. **User Authorization**: An `NSOpenPanel` targeting the document's parent directory is presented.
4. **Bookmark Creation**: Upon selection, `FolderAccessManager` creates a security-scoped bookmark:
   ```swift
   let bookmarkData = try url.bookmarkData(
       options: .withSecurityScope,
       includingResourceValuesForKeys: nil,
       relativeTo: nil
   )
   ```
5. **Persistence & Access**: Save bookmark to `UserDefaults`. On app launch or document opening, resolve bookmark and call `startAccessingSecurityScopedResource()` before reading assets, and `stopAccessingSecurityScopedResource()` when finished.
