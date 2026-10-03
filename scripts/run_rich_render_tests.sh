#!/bin/bash
# Headless KaTeX / Mermaid rendering checks for RichContentRenderer.
set -eo pipefail
cd "$(dirname "$0")/.."
OUT="build/rich-render"; mkdir -p "$OUT"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
CORE="Swash/Markdown/*.swift Swash/PlatformTypes.swift Swash/RichContentRenderer.swift Swash/MarkdownEditorStyler.swift Swash/FormatCommands.swift Swash/MarkdownFlavor.swift Swash/FolderAccessManager.swift Swash/MarkdownParser.swift Swash/MarkdownPreviewView.swift Swash/DetectedLink.swift Swash/InteractiveTableView.swift Swash/SwashTextView.swift Swash/BubbleMenuView.swift"
swiftc -O -target arm64-apple-macos14.0 -sdk "$SDK" $CORE Tests/RichRender/main.swift -o "$OUT/runner"
SWASH_RENDER_RESOURCES="$PWD/Swash/Rendering" "$OUT/runner" "$OUT"
