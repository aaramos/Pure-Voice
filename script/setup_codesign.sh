#!/usr/bin/env bash
set -euo pipefail

CERT_NAME="${PUREVOICE_CODESIGN_IDENTITY:-Pure Voice Local Development}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning -v 2>/dev/null | grep -Fq "\"$CERT_NAME\""; then
  echo "Code signing identity already exists: $CERT_NAME"
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

security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$CERT_PEM" >/dev/null 2>&1 || {
    echo "warning: certificate imported, but macOS did not add explicit trust automatically." >&2
    echo "If codesign cannot use it, open Keychain Access and trust '$CERT_NAME' for code signing." >&2
  }

security find-identity -p codesigning -v | grep -F "\"$CERT_NAME\"" >/dev/null
echo "Created code signing identity: $CERT_NAME"
