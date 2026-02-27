#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SlackmojiEverywhere"
VERSION="${1:-0.1.0}"

DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/dmg"
APP_BUNDLE="$STAGING_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"

swift build --package-path "$ROOT_DIR" -c release

if [[ -L "$ROOT_DIR/.build/release" ]]; then
  RELEASE_DIR="$(cd "$ROOT_DIR/.build/release" && pwd)"
else
  RELEASE_DIR="$ROOT_DIR/.build/release"
fi

BIN_PATH="$RELEASE_DIR/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Release binary not found at $BIN_PATH" >&2
  exit 1
fi

RESOURCE_BUNDLE_PATH=""
for candidate in \
  "$RELEASE_DIR/${APP_NAME}_${APP_NAME}.bundle" \
  "$RELEASE_DIR/${APP_NAME}_${APP_NAME}.resources"
do
  if [[ -d "$candidate" ]]; then
    RESOURCE_BUNDLE_PATH="$candidate"
    break
  fi
done

rm -rf "$STAGING_DIR"
rm -f "$DMG_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

if [[ -n "$RESOURCE_BUNDLE_PATH" ]]; then
  cp -R "$RESOURCE_BUNDLE_PATH" "$RESOURCES_DIR/"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>com.haasonsaas.slackmojierrywhere</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

ln -sfn /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "DMG created at: $DMG_PATH"
