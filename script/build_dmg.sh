#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Pure Voice"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
DMG_PATH="$ROOT_DIR/dist/PureVoice-1.1.2.dmg"
STAGING_DIR="$ROOT_DIR/dist/dmg-staging"
CODE_SIGN_IDENTITY="${PUREVOICE_CODESIGN_IDENTITY:-Pure Voice Local Development}"
CODE_SIGN_KEYCHAIN="${PUREVOICE_CODESIGN_KEYCHAIN:-$HOME/Library/Application Support/Pure Voice/Signing/PureVoice.keychain-db}"

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

if [[ -f "$CODE_SIGN_KEYCHAIN" ]] && security find-identity -p codesigning -v "$CODE_SIGN_KEYCHAIN" 2>/dev/null | grep -Fq "\"$CODE_SIGN_IDENTITY\""; then
  codesign --force --sign "$CODE_SIGN_IDENTITY" --keychain "$CODE_SIGN_KEYCHAIN" "$DMG_PATH" >/dev/null
elif security find-identity -p codesigning -v 2>/dev/null | grep -Fq "\"$CODE_SIGN_IDENTITY\""; then
  codesign --force --sign "$CODE_SIGN_IDENTITY" "$DMG_PATH" >/dev/null
else
  echo "warning: signing DMG with ad-hoc identity; run ./script/setup_codesign.sh to stabilize macOS permissions" >&2
  codesign --force --sign - "$DMG_PATH" >/dev/null
fi

echo "$DMG_PATH"
