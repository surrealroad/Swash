#!/bin/bash
# Builds and runs the CommonMark 0.31.2 + GFM extension conformance suite against
# the Markdown engine (PixerateMarkdown, from the Pixerate editor repo; see
# scripts/pixerate_markdown.sh). The fixtures and the parser and highlighter checks come from
# the engine's own tests at the pinned revision. Extra arguments are passed to the runner:
#   --verbose            print every failure
#   --example N          run (and print) a single example
#   --section NAME       run a single spec section
set -eo pipefail
cd "$(dirname "$0")/.."
source scripts/pixerate_markdown.sh
CHECKS="$PIXERATE_EDITOR/packages/swift/Tests/PixerateMarkdownTests"

BUILD_DIR="build/commonmark-spec"
mkdir -p "$BUILD_DIR"
BIN="$BUILD_DIR/commonmark-spec-runner"

swiftc -O \
  -target arm64-apple-macos14.0 \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  $PIXERATE_MARKDOWN \
  Tests/CommonMarkSpec/SpecRunner.swift \
  "$CHECKS/SpecStructure.swift" \
  "$CHECKS/ParserChecks.swift" \
  "$CHECKS/CodeHighlighterChecks.swift" \
  -o "$BIN"

"$BIN" "$CHECKS/Fixtures" "$@"
