#!/bin/bash
# Regenerates Resources/AppIcon.icns from the drawing code in PaperclipIcon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build
xcrun swiftc -O -o build/make-icon scripts/icon/main.swift Sources/Clipman/PaperclipIcon.swift
rm -rf build/AppIcon.iconset
build/make-icon build/AppIcon.iconset build/icon-previews
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns (previews in build/icon-previews)"
