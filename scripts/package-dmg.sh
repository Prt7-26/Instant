#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  "") bash scripts/build.sh ;;
  --skip-build) ;;
  *) printf 'Usage: bash scripts/package-dmg.sh [--skip-build]\n' >&2; exit 1 ;;
esac

APP_PATH="$PWD/build/Instant.app"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")
ARCHS=$(/usr/bin/lipo -archs "$APP_PATH/Contents/MacOS/Instant")
case "$VERSION-$BUILD_NUMBER" in
  *[!0-9A-Za-z.-]*) printf 'Invalid version or build number.\n' >&2; exit 1 ;;
esac
case "$ARCHS" in
  arm64) ARCH_LABEL=arm64 ;;
  x86_64) ARCH_LABEL=x86_64 ;;
  'x86_64 arm64'|'arm64 x86_64') ARCH_LABEL=universal ;;
  *) printf 'Unsupported architectures: %s\n' "$ARCHS" >&2; exit 1 ;;
esac

mkdir -p dist
IMAGE_NAME="Instant-$VERSION-$BUILD_NUMBER-$ARCH_LABEL.dmg"
IMAGE_PATH="$PWD/dist/$IMAGE_NAME"
if [ -e "$IMAGE_PATH" ] || [ -e "$IMAGE_PATH.sha256" ]; then
  printf 'Release already exists; increment the version/build number before publishing: %s\n' "$IMAGE_PATH" >&2
  exit 1
fi

STAGING_PATH=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/instant-dmg.XXXXXX")
trap 'rm -rf "$STAGING_PATH"' EXIT
mkdir "$STAGING_PATH/contents"
/usr/bin/ditto "$APP_PATH" "$STAGING_PATH/contents/Instant.app"
ln -s /Applications "$STAGING_PATH/contents/Applications"
cp Resources/DMG-Readme.txt "$STAGING_PATH/contents/安装说明.txt"
/usr/bin/hdiutil create -volname Instant -srcfolder "$STAGING_PATH/contents" \
  -format UDZO -fs HFS+ "$STAGING_PATH/release.dmg"
/usr/bin/hdiutil verify "$STAGING_PATH/release.dmg"
mv "$STAGING_PATH/release.dmg" "$IMAGE_PATH"
(cd dist && /usr/bin/shasum -a 256 "$IMAGE_NAME" > "$IMAGE_NAME.sha256")
printf 'DMG: %s\nSHA-256: %s.sha256\n' "$IMAGE_PATH" "$IMAGE_PATH"
