#!/bin/bash
# Builds and runs the CommonMark 0.31.2 + GFM extension conformance suite against
# Swash's Markdown parser (Swash/Markdown). Extra arguments are passed to the runner:
#   --verbose            print every failure
#   --example N          run (and print) a single example
#   --section NAME       run a single spec section
set -eo pipefail
cd "$(dirname "$0")/.."

BUILD_DIR="build/commonmark-spec"
mkdir -p "$BUILD_DIR"
BIN="$BUILD_DIR/commonmark-spec-runner"

swiftc -O \
  -target arm64-apple-macos14.0 \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  Swash/Markdown/*.swift \
  Tests/CommonMarkSpec/SpecRunner.swift \
  Tests/CommonMarkSpec/ParserChecks.swift \
  -o "$BIN"

"$BIN" Tests/CommonMarkSpec/fixtures "$@"

# HTMLToMarkdown runs on HTMLLiteDOM where Foundation's XMLDocument is missing (iOS). Build the
# checks again with that parser forced on, so both paths stay in step.
swiftc -O -D SWASH_HTML_LITE -module-name main \
  -target arm64-apple-macos14.0 \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  Swash/Markdown/*.swift \
  Tests/CommonMarkSpec/SpecRunner.swift \
  Tests/CommonMarkSpec/ParserChecks.swift \
  -o "$BUILD_DIR/commonmark-spec-runner-lite"

echo "--- HTML conversion with HTMLLiteDOM ---"
"$BUILD_DIR/commonmark-spec-runner-lite" Tests/CommonMarkSpec/fixtures "$@" | grep -E "HTML paste conversion|❌ html"
