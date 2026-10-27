#!/usr/bin/env bash
# Captures the README hero screenshots in Light and Dark Mode (docs/images/screenshot-*.png):
# the Debug build of Swash editing docs/images/Trip Planning.md with the outline open.
# Needs Screen Recording permission for the terminal running it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DerivedData/Build/Products/Debug/Swash.app"
SAMPLE="$ROOT/docs/images/Trip Planning.md"
OUT="$ROOT/docs/images"

if [ ! -d "$APP" ]; then
    xcodebuild -scheme Swash -destination 'generic/platform=macOS' -configuration Debug \
        -derivedDataPath "$ROOT/build/DerivedData" build CODE_SIGN_IDENTITY="-" >/dev/null
fi

for appearance in light dark; do
    pkill -x Swash || true
    sleep 1
    style=()
    [ "$appearance" = dark ] && style=(-AppleInterfaceStyle Dark)
    # Arguments override the app's defaults for this launch only
    open -n -a "$APP" "$SAMPLE" --args -showOutline YES -NSQuitAlwaysKeepsWindows NO "${style[@]}"
    sleep 6
    id="$(swift "$ROOT/scripts/get_window_id.swift")"
    screencapture -o -l "$id" "$OUT/screenshot-$appearance.png"
    echo "Wrote $OUT/screenshot-$appearance.png"
done
pkill -x Swash || true
