#!/bin/bash
# Builds Clipman with SwiftPM and wraps it into build/Clipman.app.
#   CONFIG=debug scripts/build-app.sh          # debug build
#   CODESIGN_IDENTITY="Developer ID Application: …" scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

[ -f Resources/AppIcon.icns ] || scripts/make-icon.sh

APP=build/Clipman.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Clipman" "$APP/Contents/MacOS/Clipman"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc by default. Use a stable identity if you want macOS to remember the
# "Paste from other apps" permission across rebuilds.
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
