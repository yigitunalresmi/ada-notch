#!/bin/zsh
# Ada'yı derler, Ada.app paketini oluşturur ve imzalar.  Kullanım: ./build.sh [run]
set -e
cd "$(dirname "$0")"
swift build -c release 2>&1 | grep -E "error|warning: unre|Compiling|Build complete|Linking" | grep -v "^$" | tail -40
BIN=".build/release/Ada"
[ -f "$BIN" ] || { echo "Derleme başarısız"; exit 1; }
APP="build/Ada.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ada"
cp Info.plist "$APP/Contents/Info.plist"
# Dil dosyaları (en.lproj, tr.lproj)
rm -rf "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Resources"
cp -R Resources/. "$APP/Contents/Resources/"
IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | awk '{print $2}')
[ -z "$IDENTITY" ] && IDENTITY="-"
codesign --force --sign "$IDENTITY" "$APP" 2>&1 | tail -1
echo "Hazır: $APP"
if [ "$1" = "run" ]; then
  pkill -x Ada 2>/dev/null || true
  sleep 0.3
  open "$APP"
fi
