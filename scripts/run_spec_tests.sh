#!/bin/bash
set -e

# Script to build and run the GFM spec compliance & snapshot runner
cd "$(dirname "$0")/.."

BUILD_DIR="build/spec-runner"
mkdir -p "$BUILD_DIR"
BIN="$BUILD_DIR/gfm-spec-runner"

EXTRAS="$(scripts/build_mac_appkit_extras.sh)"

echo "Compiling GFM Spec Runner..."
swiftc $EXTRAS \
  -O \
  -target arm64-apple-macos14.0 \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  Swash/PlatformTypes.swift \
  Swash/EditorSupport.swift \
  Swash/MarkdownFlavor.swift \
  Swash/FolderAccessManager.swift \
  Swash/MarkdownParser.swift \
  Swash/Markdown/*.swift \
  Swash/MarkdownEditorStyler.swift \
  Swash/CodeHighlightTheme.swift \
  Swash/RichContentRenderer.swift \
  Swash/FormatCommands.swift \
  Swash/MarkdownPreviewView.swift \
  Swash/DetectedLink.swift \
  Swash/BubbleMenuView.swift \
  Swash/InteractiveTableView.swift \
  Swash/SwashTextView.swift Swash/FolderIndex.swift Swash/WritingModes.swift Swash/EditorTypography.swift Swash/ImageInsertion.swift \
  Tests/GFMSpec/GFMSpecRunner.swift \
  -o "$BIN"

echo "Running GFM Spec Tests..."
"$BIN"
