#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Pure Voice"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
DMG_PATH="$ROOT_DIR/dist/PureVoice-0.1.0.dmg"
STAGING_DIR="$ROOT_DIR/dist/dmg-staging"

CONFIGURATION=release "$ROOT_DIR/script/build_and_run.sh" --verify
pkill -x "PureVoice" >/dev/null 2>&1 || true

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

codesign --force --sign - "$DMG_PATH" >/dev/null

echo "$DMG_PATH"
