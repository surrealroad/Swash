#!/bin/bash
# Builds and runs the shared Markdown editing corpus (@pixerate/markdown-conformance, installed
# by `npm ci`) against Swash's editing engine (Swash/Markdown, Foundation only). Extra
# arguments are passed to the runner:
#   --verbose     print every case
#   --case ID     run (and print) a single case
set -eo pipefail
cd "$(dirname "$0")/.."

FIXTURES="node_modules/@pixerate/markdown-conformance/fixtures"
if [[ ! -d "$FIXTURES" ]]; then
  echo "error: $FIXTURES not found. Run \`npm ci\` first." >&2
  exit 2
fi

BUILD_DIR="build/markdown-conformance"
mkdir -p "$BUILD_DIR"
BIN="$BUILD_DIR/conformance-runner"

swiftc -O \
  -target arm64-apple-macos14.0 \
  -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  Swash/Markdown/*.swift \
  Tests/MarkdownConformance/ConformanceRunner.swift \
  -o "$BIN"

"$BIN" "$FIXTURES" "$@"
