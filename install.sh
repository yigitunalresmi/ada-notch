#!/bin/bash
# Ada'nın son sürümünü indirip Uygulamalar klasörüne kurar ve başlatır.
#   curl -fsSL https://raw.githubusercontent.com/yigitunalresmi/ada-notch/main/install.sh | bash
set -e
URL="https://github.com/yigitunalresmi/ada-notch/releases/latest/download/Ada.zip"
DEST="${ADA_DEST:-/Applications}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Ada indiriliyor / Downloading Ada…"
curl -fsSL "$URL" -o "$TMP/Ada.zip"
/usr/bin/ditto -x -k "$TMP/Ada.zip" "$TMP"
[ -d "$TMP/Ada.app" ] || { echo "İndirilen paket geçersiz / Invalid download."; exit 1; }
/usr/bin/codesign --verify --strict "$TMP/Ada.app" || { echo "İmza doğrulanamadı / Signature check failed."; exit 1; }

pkill -x Ada 2>/dev/null || true
sleep 0.5
rm -rf "$DEST/Ada.app"
mv "$TMP/Ada.app" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/Ada.app" 2>/dev/null || true
[ -z "$ADA_NO_OPEN" ] && open "$DEST/Ada.app"
echo "Kuruldu / Installed: $DEST/Ada.app"
