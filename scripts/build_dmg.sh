#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SlackmojiEverywhere"
VERSION="${1:-dev}"

BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.haasonsaas.slackmojierrywhere}"
MINIMUM_SYSTEM_VERSION="${MINIMUM_SYSTEM_VERSION:-13.0}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
APPLE_NOTARY_KEYCHAIN_PROFILE="${APPLE_NOTARY_KEYCHAIN_PROFILE:-}"
SKIP_BUILD="${SKIP_BUILD:-0}"

DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/dmg"
APP_BUNDLE="$STAGING_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"

if [[ "$SKIP_BUILD" != "1" ]]; then
  swift build --package-path "$ROOT_DIR" -c release
fi

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

if [[ -z "$RESOURCE_BUNDLE_PATH" ]]; then
  echo "Expected resource bundle was not found in $RELEASE_DIR" >&2
  exit 1
fi

rm -rf "$STAGING_DIR"
rm -f "$DMG_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cp -R "$RESOURCE_BUNDLE_PATH" "$APP_BUNDLE/"

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
  <string>${BUNDLE_IDENTIFIER}</string>
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
  <string>${MINIMUM_SYSTEM_VERSION}</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
fi

ln -sfn /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
fi

if [[ -n "$APPLE_NOTARY_KEYCHAIN_PROFILE" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$APPLE_NOTARY_KEYCHAIN_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
fi

echo "DMG created at: $DMG_PATH"
