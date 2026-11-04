#!/usr/bin/env bash
# Captures the README hero screenshots in Light and Dark Mode (docs/images/screenshot-*.png):
# the Debug build of Swash editing docs/images/Trip Planning.md with the outline open.
# Only the copy of Swash this script launches is captured and quit. Needs Screen Recording
# permission for the terminal running it.
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
    style=(-NSRequiresAquaSystemAppearance YES)
    [ "$appearance" = dark ] && style=(-AppleInterfaceStyle Dark)
    # Opened through Launch Services so the sandboxed app may read the file; the arguments
    # override the app's defaults for this launch only
    open -n -a "$APP" "$SAMPLE" --args -showOutline YES -NSQuitAlwaysKeepsWindows NO \
        -suppressDefaultAppPrompt YES "${style[@]}"
    sleep 8
    pid="$(pgrep -n -f "$APP/Contents/MacOS/Swash")"
    id="$(swift "$ROOT/scripts/get_window_id.swift" "$pid")"
    screencapture -o -l "$id" "$OUT/screenshot-$appearance.png"
    kill "$pid"
    wait "$pid" 2>/dev/null || true
    echo "Wrote $OUT/screenshot-$appearance.png"
done
