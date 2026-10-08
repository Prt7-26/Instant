#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ICON_SET_DIR="$PWD/build/AppIcon.iconset"
swift scripts/render-icon.swift Resources/AppIcon.svg "$ICON_SET_DIR"
iconutil --convert icns "$ICON_SET_DIR" --output Resources/AppIcon.icns
cp "$ICON_SET_DIR/icon_512x512@2x.png" Resources/AppIcon.png
