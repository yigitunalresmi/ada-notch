#!/bin/zsh
# Dağıtım için Ada.dmg ve Ada.zip üretir; "publish" verilirse GitHub'da sürüm yayımlar.
#
#   ./release.sh            dist/ altında paketleri üretir
#   ./release.sh publish    paketleri üretir ve GitHub Releases'e yükler
#
# Apple onayı (notarization) kendiliğinden devreye girer, şu ikisi varsa:
#   1. Anahtar Zinciri'nde bir "Developer ID Application" sertifikası
#   2. `xcrun notarytool store-credentials ada-notary` ile kaydedilmiş onay bilgisi
# İkisinden biri eksikse paket yerel (ad-hoc) imzayla üretilir.
#
# İsteğe bağlı ortam değişkenleri (otomatik algılamayı geçersiz kılar):
#   SIGN_IDENTITY   İmza kimliği
#   NOTARY_PROFILE  notarytool profil adı
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
# Çıktı klasörü Swift sürümüne göre değişir; derleyiciye sor.
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path 2>/dev/null | tail -1)/Ada"
[ -f "$BIN" ] || { echo "Derlenen dosya bulunamadı: $BIN"; exit 1; }

rm -rf dist && mkdir -p dist/Ada.app/Contents/MacOS dist/Ada.app/Contents/Resources
APP="dist/Ada.app"
cp "$BIN" "$APP/Contents/MacOS/Ada"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Resources/. "$APP/Contents/Resources/"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" -c "Set :CFBundleShortVersionString $VERSION" \
  -c "Add :AdaCommit string $COMMIT" -c "Add :AdaChannel string release" "$PLIST"

# Developer ID sertifikası ve onay profili varsa kullan.
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $2}')
fi
if [ -n "$SIGN_IDENTITY" ] && [ -z "$NOTARY_PROFILE" ]; then
  if xcrun notarytool history --keychain-profile ada-notary > /dev/null 2>&1; then NOTARY_PROFILE="ada-notary"; fi
fi
IDENTITY="${SIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
  echo "İmza: yerel (ad-hoc) — Apple onayı yok"
elif [ -n "$NOTARY_PROFILE" ]; then
  echo "İmza: Developer ID — Apple onayı alınacak"
else
  echo "İmza: Developer ID — onay profili (ada-notary) bulunamadı, Apple onayı alınmayacak"
fi
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
[ "$IDENTITY" != "-" ] && codesign --force --timestamp --sign "$IDENTITY" dist/Ada.dmg

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
