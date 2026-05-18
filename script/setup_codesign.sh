#!/usr/bin/env bash
set -euo pipefail

CERT_NAME="${PUREVOICE_CODESIGN_IDENTITY:-Pure Voice Local Development}"
SIGNING_DIR="${HOME}/Library/Application Support/Pure Voice/Signing"
KEYCHAIN="${PUREVOICE_CODESIGN_KEYCHAIN:-$SIGNING_DIR/PureVoice.keychain-db}"
KEYCHAIN_PASSWORD="${PUREVOICE_CODESIGN_KEYCHAIN_PASSWORD:-purevoice-local-dev}"

mkdir -p "$(dirname "$KEYCHAIN")"

if [[ ! -f "$KEYCHAIN" ]]; then
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
  security set-keychain-settings -lut 21600 "$KEYCHAIN" >/dev/null
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

if security find-identity -p codesigning -v "$KEYCHAIN" 2>/dev/null | grep -Fq "\"$CERT_NAME\""; then
  echo "Code signing identity already exists: $CERT_NAME"
  echo "Keychain: $KEYCHAIN"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CERT_PEM="$TMP_DIR/purevoice-codesign.pem"
KEY_PEM="$TMP_DIR/purevoice-codesign.key"
PKCS12="$TMP_DIR/purevoice-codesign.p12"
PKCS12_PASSWORD="purevoice-local-dev"

openssl req \
  -x509 \
  -newkey rsa:2048 \
  -nodes \
  -days 3650 \
  -keyout "$KEY_PEM" \
  -out "$CERT_PEM" \
  -subj "/CN=$CERT_NAME/" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" >/dev/null 2>&1

openssl pkcs12 \
  -export \
  -legacy \
  -inkey "$KEY_PEM" \
  -in "$CERT_PEM" \
  -out "$PKCS12" \
  -passout "pass:$PKCS12_PASSWORD" >/dev/null 2>&1

security import "$PKCS12" \
  -k "$KEYCHAIN" \
  -P "$PKCS12_PASSWORD" \
  -A \
  -T /usr/bin/codesign >/dev/null

security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN" >/dev/null

security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$CERT_PEM" >/dev/null 2>&1 || {
    echo "warning: certificate imported, but macOS did not add explicit trust automatically." >&2
    echo "If codesign cannot use it, open Keychain Access and trust '$CERT_NAME' for code signing." >&2
  }

security find-identity -p codesigning -v "$KEYCHAIN" | grep -F "\"$CERT_NAME\"" >/dev/null
echo "Created code signing identity: $CERT_NAME"
echo "Keychain: $KEYCHAIN"
