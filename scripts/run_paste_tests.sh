#!/bin/bash
# Checks for Swash's additions to the engine's HTML paste conversion (Confluence and Jira images).
set -eo pipefail
cd "$(dirname "$0")/.."
source scripts/pixerate_markdown.sh
OUT="build/paste"; mkdir -p "$OUT"
swiftc -O -target arm64-apple-macos14.0 -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  $PIXERATE_MARKDOWN Swash/PixerateMarkdownExtensions.swift Tests/Paste/main.swift -o "$OUT/runner"
"$OUT/runner"
