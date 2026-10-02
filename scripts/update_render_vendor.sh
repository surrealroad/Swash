#!/bin/bash
# Refreshes the bundled KaTeX and Mermaid files in Swash/Rendering/ from npm.
# Usage: scripts/update_render_vendor.sh [katex-version] [mermaid-version]
# Resources are copied flat (Xcode's synchronised groups flatten them into the bundle root),
# so the KaTeX stylesheet's font URLs are rewritten to drop the fonts/ prefix and keep only woff2.
set -euo pipefail
KATEX_VERSION="${1:-0.19.0}"
MERMAID_VERSION="${2:-12.1.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Swash/Rendering"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"
npm pack "katex@$KATEX_VERSION" "mermaid@$MERMAID_VERSION" --silent >/dev/null
mkdir katex mermaid
tar -xzf "katex-$KATEX_VERSION.tgz" -C katex
tar -xzf "mermaid-$MERMAID_VERSION.tgz" -C mermaid

mkdir -p "$DEST"
rm -f "$DEST"/KaTeX_*.woff2
cp katex/package/dist/katex.min.js "$DEST/katex.min.js"
cp katex/package/dist/contrib/mhchem.min.js "$DEST/katex-mhchem.min.js"
cp katex/package/dist/fonts/*.woff2 "$DEST/"
# Keep only the woff2 source of each @font-face, without the fonts/ directory
sed -E -e 's#,url\(fonts/[^)]*\.woff\) format\("woff"\)##g' \
       -e 's#,url\(fonts/[^)]*\.ttf\) format\("truetype"\)##g' \
       -e 's#url\(fonts/#url(#g' \
    katex/package/dist/katex.min.css > "$DEST/katex.min.css"
cp katex/package/LICENSE "$DEST/KaTeX-LICENSE.txt"
cp mermaid/package/dist/mermaid.min.js "$DEST/mermaid.min.js"
cp mermaid/package/LICENSE "$DEST/Mermaid-LICENSE.txt"
printf 'katex %s\nmermaid %s\n' "$KATEX_VERSION" "$MERMAID_VERSION" > "$DEST/VENDOR-VERSIONS.txt"
echo "Updated $DEST (KaTeX $KATEX_VERSION, Mermaid $MERMAID_VERSION)"
