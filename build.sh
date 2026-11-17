#!/bin/zsh
# Ada'yı derler, Ada.app paketini oluşturur ve imzalar.  Kullanım: ./build.sh [run]
set -e
cd "$(dirname "$0")"
LOG=$(mktemp)
if ! swift build -c release > "$LOG" 2>&1; then
  grep -E "error" "$LOG" | head -20
  echo "Derleme başarısız / Build failed"
  rm -f "$LOG"
  exit 1
fi
grep -E "Build complete" "$LOG" || true
rm -f "$LOG"
BIN=".build/release/Ada"
[ -f "$BIN" ] || { echo "Derleme başarısız / Build failed"; exit 1; }
APP="build/Ada.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ada"
cp Info.plist "$APP/Contents/Info.plist"
# Dil dosyaları (en.lproj, tr.lproj)
rm -rf "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Resources"
cp -R Resources/. "$APP/Contents/Resources/"
# Sürüm bilgisi: güncelleyici hangi commit'ten derlendiğini ve kaynağın yerini buradan okur.
PLIST="$APP/Contents/Info.plist"
COMMIT=$(git rev-parse HEAD 2>/dev/null || true)
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
[ -n "$COMMIT" ] && /usr/libexec/PlistBuddy -c "Add :AdaCommit string $COMMIT" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :AdaSourcePath string $PWD" "$PLIST"
IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | awk '{print $2}')
[ -z "$IDENTITY" ] && IDENTITY="-"
codesign --force --sign "$IDENTITY" "$APP" 2>&1 | tail -1
echo "Hazır: $APP"
if [ "$1" = "run" ]; then
  pkill -x Ada 2>/dev/null || true
  sleep 0.3
  open "$APP"
fi
