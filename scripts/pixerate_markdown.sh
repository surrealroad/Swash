#!/bin/bash
# Sourced by the test scripts: builds the PixerateMarkdown module (the Markdown engine, in the
# Pixerate editor repo) so the swiftc runners can import it, as the Xcode build does through
# SwiftPM. Sets:
#   PIXERATE_EDITOR    the editor checkout the engine, its checks and the conformance corpus come from
#   PIXERATE_MARKDOWN  swiftc flags that import and link the module
#
# The engine comes from the revision Package.resolved pins, fetched (sparsely) into
# build/pixerate-editor. To test against a local checkout instead, set PIXERATE_EDITOR_DIR.

PIXERATE_REPO_URL="https://github.com/Pixerate/editor.git"
PIXERATE_SPARSE_PATHS=(packages/swift/Sources/PixerateMarkdown packages/swift/Tests/PixerateMarkdownTests packages/markdown-conformance)

pixerate_pinned_revision() {
  python3 - "Swash.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved" <<'PY'
import json, sys
pins = json.load(open(sys.argv[1]))["pins"]
print(next(p["state"]["revision"] for p in pins if p["location"].rstrip("/").removesuffix(".git").lower().endswith("pixerate/editor")))
PY
}

if [[ -n "$PIXERATE_EDITOR_DIR" ]]; then
  PIXERATE_EDITOR="$(cd "$PIXERATE_EDITOR_DIR" && pwd)"
else
  PIXERATE_EDITOR="$PWD/build/pixerate-editor"
  revision="$(pixerate_pinned_revision)"
  if [[ "$(git -C "$PIXERATE_EDITOR" rev-parse HEAD 2>/dev/null)" != "$revision" ]]; then
    echo "Fetching PixerateMarkdown at ${revision:0:12}…" >&2
    if [[ ! -d "$PIXERATE_EDITOR/.git" ]]; then
      rm -rf "$PIXERATE_EDITOR"
      git clone --quiet --filter=blob:none --no-checkout "$PIXERATE_REPO_URL" "$PIXERATE_EDITOR"
      git -C "$PIXERATE_EDITOR" sparse-checkout set "${PIXERATE_SPARSE_PATHS[@]}"
    fi
    git -C "$PIXERATE_EDITOR" fetch --quiet origin "$revision"
    git -C "$PIXERATE_EDITOR" checkout --quiet --detach "$revision"
  fi
fi

PIXERATE_MARKDOWN_SOURCES="$PIXERATE_EDITOR/packages/swift/Sources/PixerateMarkdown"
if [[ ! -d "$PIXERATE_MARKDOWN_SOURCES" ]]; then
  echo "error: $PIXERATE_MARKDOWN_SOURCES not found" >&2
  exit 2
fi

# One build per source state; -enable-testing lets the shared checks use `@testable import`.
pixerate_hash="$(cat "$PIXERATE_MARKDOWN_SOURCES"/*.swift | shasum | cut -c1-12)"
PIXERATE_MARKDOWN_DIR="$PWD/build/pixerate-markdown/$pixerate_hash"
if [[ ! -f "$PIXERATE_MARKDOWN_DIR/libPixerateMarkdown.a" ]]; then
  echo "Building PixerateMarkdown…" >&2
  mkdir -p "$PIXERATE_MARKDOWN_DIR"
  swiftc -O -enable-testing -parse-as-library -swift-version 6 \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -target arm64-apple-macos14.0 \
    -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    -module-name PixerateMarkdown \
    -emit-module -emit-module-path "$PIXERATE_MARKDOWN_DIR/PixerateMarkdown.swiftmodule" \
    -emit-library -static -o "$PIXERATE_MARKDOWN_DIR/libPixerateMarkdown.a" \
    "$PIXERATE_MARKDOWN_SOURCES"/*.swift
fi
PIXERATE_MARKDOWN="-I $PIXERATE_MARKDOWN_DIR -L $PIXERATE_MARKDOWN_DIR -lPixerateMarkdown"
