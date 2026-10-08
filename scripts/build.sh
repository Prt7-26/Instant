#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-icon.sh
swift build --build-system native -c release --product Instant
BIN_DIR="$(swift build --build-system native -c release --show-bin-path)"
APP_DIR="$PWD/build/Instant.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/Instant" "$APP_DIR/Contents/MacOS/Instant"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP_DIR/Contents/Resources/LICENSE.txt"
cp Vendor/MaterialView/LICENSE "$APP_DIR/Contents/Resources/MaterialView-LICENSE.txt"
codesign --force --sign - --identifier com.instant.app "$APP_DIR"
touch "$APP_DIR"
printf '%s\n' "$APP_DIR"
