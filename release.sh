#!/bin/zsh
# Dağıtım için Ada.dmg ve Ada.zip üretir; "publish" verilirse GitHub'da sürüm yayımlar.
#
#   ./release.sh            dist/ altında paketleri üretir
#   ./release.sh publish    paketleri üretir ve GitHub Releases'e yükler
#
# İsteğe bağlı ortam değişkenleri:
#   SIGN_IDENTITY   İmza kimliği (ör. "Developer ID Application: …"). Verilmezse yerel (ad-hoc) imza kullanılır.
#   NOTARY_PROFILE  `xcrun notarytool store-credentials` ile kaydedilmiş profil adı. Verilirse Apple onayı alınır.
set -e
cd "$(dirname "$0")"

if [ -n "$(git status --porcelain)" ]; then
  echo "Önce değişiklikleri commit edin / Commit your changes first."; exit 1
fi
BUILD=$(git rev-list --count HEAD)
COMMIT=$(git rev-parse HEAD)
VERSION="1.0.$BUILD"
echo "Ada $VERSION derleniyor (Apple Silicon + Intel)…"

LOG=$(mktemp)
if ! swift build -c release --arch arm64 --arch x86_64 > "$LOG" 2>&1; then
  grep -E "error" "$LOG" | head -20; echo "Derleme başarısız / Build failed"; exit 1
fi
BIN=".build/apple/Products/Release/Ada"
[ -f "$BIN" ] || { echo "Derlenen dosya bulunamadı"; exit 1; }

rm -rf dist && mkdir -p dist/Ada.app/Contents/MacOS dist/Ada.app/Contents/Resources
APP="dist/Ada.app"
cp "$BIN" "$APP/Contents/MacOS/Ada"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Resources/. "$APP/Contents/Resources/"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" -c "Set :CFBundleShortVersionString $VERSION" \
  -c "Add :AdaCommit string $COMMIT" -c "Add :AdaChannel string release" "$PLIST"

IDENTITY="${SIGN_IDENTITY:--}"
if [ -n "$NOTARY_PROFILE" ]; then
  # Apple onayı için güçlendirilmiş çalışma zamanı ve yetkiler gerekir.
  codesign --force --options runtime --timestamp --entitlements Ada.entitlements --sign "$IDENTITY" "$APP"
else
  codesign --force --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

# Sürükle-bırak kurulum için disk görüntüsü
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Ada" -srcfolder "$STAGE" -ov -format UDZO -quiet dist/Ada.dmg
rm -rf "$STAGE"

if [ -n "$NOTARY_PROFILE" ]; then
  echo "Apple onayı bekleniyor…"
  xcrun notarytool submit dist/Ada.dmg --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple dist/Ada.dmg
  xcrun stapler staple "$APP"
fi

# Uygulama içi güncelleyici ve kurulum betiği bu zip'i kullanır.
ditto -c -k --keepParent "$APP" dist/Ada.zip
echo "Hazır: dist/Ada.dmg, dist/Ada.zip  (sürüm $VERSION, mimariler: $(lipo -archs "$APP/Contents/MacOS/Ada"))"

if [ "$1" = "publish" ]; then
  LAST=$(git describe --tags --abbrev=0 2>/dev/null || true)
  if [ -n "$LAST" ]; then NOTES=$(git log --format='- %s' "$LAST"..HEAD); else NOTES=$(git log --format='- %s' -n 12); fi
  gh release create "v$VERSION" dist/Ada.dmg dist/Ada.zip --title "Ada $VERSION" --notes "$NOTES"
  echo "Yayımlandı: v$VERSION"
fi
