#!/bin/bash
# Headless HTML and PDF export checks for DocumentExporter.
set -eo pipefail
cd "$(dirname "$0")/.."
source scripts/pixerate_markdown.sh
OUT="build/export"; mkdir -p "$OUT"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
EXTRAS="$(scripts/build_mac_appkit_extras.sh)"
CORE="$PIXERATE_MARKDOWN Swash/PixerateMarkdownExtensions.swift Swash/PlatformTypes.swift Swash/EditorSupport.swift Swash/RichContentRenderer.swift Swash/MarkdownEditorStyler.swift Swash/CodeHighlightTheme.swift Swash/FormatCommands.swift Swash/MarkdownFlavor.swift Swash/FolderAccessManager.swift Swash/MarkdownParser.swift Swash/MarkdownPreviewView.swift Swash/DetectedLink.swift Swash/InteractiveTableView.swift Swash/SwashTextView.swift Swash/FolderIndex.swift Swash/WritingModes.swift Swash/EditorTypography.swift Swash/ImageInsertion.swift Swash/BubbleMenuView.swift Swash/DocumentExporter.swift"
swiftc $EXTRAS -O -target arm64-apple-macos14.0 -sdk "$SDK" $CORE Tests/Export/main.swift -o "$OUT/runner"
SWASH_RENDER_RESOURCES="$PWD/Swash/Rendering" "$OUT/runner" "$OUT"
