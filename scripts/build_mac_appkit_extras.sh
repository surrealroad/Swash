#!/bin/bash
# Builds Packages/MacAppKitExtras as a static library for the swiftc-based test runners and prints
# the compiler flags that link it. Usage: EXTRAS="$(scripts/build_mac_appkit_extras.sh)"
set -eo pipefail
cd "$(dirname "$0")/.."
OUT="build/mac-appkit-extras"; mkdir -p "$OUT"
swiftc -O -parse-as-library -target arm64-apple-macos14.0 -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -module-name MacAppKitExtras -emit-module -emit-module-path "$OUT/MacAppKitExtras.swiftmodule" \
  -emit-library -static -o "$OUT/libMacAppKitExtras.a" \
  Packages/MacAppKitExtras/Sources/MacAppKitExtras/*.swift >&2
echo "-I $PWD/$OUT -L $PWD/$OUT -lMacAppKitExtras"
