#!/usr/bin/env bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

APP_PATH="$REPO_ROOT/build/Build/Products/Release/Swash.app"
SAMPLE_FILE="$REPO_ROOT/scripts/sample_preview.md"
OUTPUT_PNG="$REPO_ROOT/Screenshot.png"

echo "=== Generating Swash README Screenshot ==="

if [ ! -d "$APP_PATH" ]; then
    echo "Swash.app not found at $APP_PATH. Building Release build..."
    xcodebuild -scheme Swash -configuration Release -derivedDataPath "$REPO_ROOT/build" CODE_SIGN_IDENTITY="-"
fi

echo "Launching Swash with sample preview file..."
open -a "$APP_PATH" "$SAMPLE_FILE"

echo "Waiting for app window to render..."
sleep 3

WINDOW_ID=""
if command -v swift &> /dev/null; then
    WINDOW_ID=$(swift "$SCRIPT_DIR/get_window_id.swift" 2>/dev/null || true)
fi

if [ -n "$WINDOW_ID" ]; then
    echo "Capturing window screenshot (Window ID: $WINDOW_ID)..."
    screencapture -l "$WINDOW_ID" "$OUTPUT_PNG" || screencapture -o "$OUTPUT_PNG"
else
    echo "Window ID not found. Capturing frontmost window..."
    screencapture -o "$OUTPUT_PNG"
fi

echo "Closing Swash..."
pkill -x "Swash" || true

if [ -s "$OUTPUT_PNG" ]; then
    echo "Successfully generated screenshot at $OUTPUT_PNG"
else
    echo "Error: Screenshot file is missing or empty!"
    exit 1
fi
