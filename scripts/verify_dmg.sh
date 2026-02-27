#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <path-to-dmg>" >&2
  exit 1
fi

DMG_PATH="$1"
APP_NAME="SlackmojiEverywhere"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH" >&2
  exit 1
fi

MOUNT_OUTPUT="$(hdiutil attach "$DMG_PATH" -nobrowse -readonly)"
MOUNT_POINT="$(echo "$MOUNT_OUTPUT" | awk '/\/Volumes\// {print $NF; exit}')"

if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
  echo "Failed to mount DMG: $DMG_PATH" >&2
  exit 1
fi

cleanup() {
  hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

APP_PATH="$MOUNT_POINT/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle missing in DMG: $APP_PATH" >&2
  exit 1
fi

BIN_PATH="$APP_PATH/Contents/MacOS/${APP_NAME}"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "App binary missing or not executable: $BIN_PATH" >&2
  exit 1
fi

BUNDLE_PATH="$APP_PATH/${APP_NAME}_${APP_NAME}.bundle"
RESOURCES_PATH="$APP_PATH/${APP_NAME}_${APP_NAME}.resources"

if [[ -d "$BUNDLE_PATH" ]]; then
  if [[ ! -f "$BUNDLE_PATH/slack_emoji_aliases.json" && ! -f "$BUNDLE_PATH/Contents/Resources/slack_emoji_aliases.json" ]]; then
    echo "Emoji aliases resource missing from bundle: $BUNDLE_PATH" >&2
    exit 1
  fi
elif [[ -d "$RESOURCES_PATH" ]]; then
  if [[ ! -f "$RESOURCES_PATH/slack_emoji_aliases.json" ]]; then
    echo "Emoji aliases resource missing from resources dir: $RESOURCES_PATH" >&2
    exit 1
  fi
else
  echo "Expected SwiftPM resource bundle not found in app bundle" >&2
  exit 1
fi

echo "DMG verification passed: $DMG_PATH"
