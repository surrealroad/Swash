#!/bin/bash
# Builds and runs the shared Markdown editing corpus (@pixerate/markdown-conformance) against
# the editing engine (PixerateMarkdown). Both come from the Pixerate editor repo at the revision
# Package.resolved pins (see scripts/pixerate_markdown.sh), so the corpus matches the engine. Extra
# arguments are passed to the runner:
#   --verbose     print every case
#   --case ID     run (and print) a single case
set -eo pipefail
cd "$(dirname "$0")/.."

source scripts/pixerate_markdown.sh
FIXTURES="$PIXERATE_EDITOR/packages/markdown-conformance/fixtures"

BUILD_DIR="build/markdown-conformance"
mkdir -p "$BUILD_DIR"
BIN="$BUILD_DIR/conformance-runner"

swiftc -O -parse-as-library \
  -target arm64-apple-macos14.0 \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  $PIXERATE_MARKDOWN \
  Tests/MarkdownConformance/ConformanceRunner.swift \
  -o "$BIN"

"$BIN" "$FIXTURES" "$@"
