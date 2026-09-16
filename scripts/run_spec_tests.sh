#!/bin/bash
set -e

# Script to build and run the GFM spec compliance & snapshot runner
cd "$(dirname "$0")/.."

BUILD_DIR="build/spec-runner"
mkdir -p "$BUILD_DIR"
BIN="$BUILD_DIR/gfm-spec-runner"

echo "Compiling GFM Spec Runner..."
swiftc \
  -O \
  -target arm64-apple-macos14.0 \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  Swash/MarkdownFlavor.swift \
  Swash/FolderAccessManager.swift \
  Swash/MarkdownParser.swift \
  Swash/MarkdownPreviewView.swift \
  Swash/DetectedLink.swift \
  Swash/BubbleMenuView.swift \
  Swash/InteractiveTableView.swift \
  Swash/SwashTextView.swift \
  Tests/GFMSpec/GFMSpecRunner.swift \
  -o "$BIN"

echo "Running GFM Spec Tests..."
"$BIN"
