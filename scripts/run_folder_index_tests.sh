#!/bin/bash
# Checks for the folder window's logic (Swash/FolderIndex.swift): scanning a folder into a tree,
# filtering by name, full-text search, and resolving relative and wiki links between notes.
set -eo pipefail
cd "$(dirname "$0")/.."
OUT="build/folder-index"; mkdir -p "$OUT"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
swiftc -O -target arm64-apple-macos14.0 -sdk "$SDK" Swash/FolderIndex.swift Tests/FolderIndex/main.swift -o "$OUT/runner"
"$OUT/runner" "$OUT/fixture"
