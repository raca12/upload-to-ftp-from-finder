#!/bin/sh
# Developer ID ile imzalar + Apple'a notarization için gönderir.
#
# Ön koşullar (bir kez):
#   1. Apple Developer Program üyeliği (99 $/yıl)
#   2. Developer ID Application sertifikası (Keychain'de)
#   3. notarytool kimlik bilgileri:
#        xcrun notarytool store-credentials "mcb-notary" \
#          --apple-id "you@example.com" --team-id "ABCDE12345" --password "app-specific-password"
#
# Kullanım:
#   DEVELOPER_ID="Developer ID Application: Ad Soyad (TEAMID)" \
#   NOTARY_PROFILE="mcb-notary" ./tools/notarize.sh 0.1.1
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
APP_NAME="Upload to FTP from Finder"
APP="$ROOT/bin/$APP_NAME.app"
DIST="$ROOT/dist"
PROFILE="${NOTARY_PROFILE:-mcb-notary}"

if [ -z "${DEVELOPER_ID:-}" ]; then
  DEVELOPER_ID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)"
fi

if [ -z "$DEVELOPER_ID" ]; then
  echo "✗ Developer ID Application sertifikası bulunamadı."
  echo "  Apple Developer hesabından sertifikayı indirip Keychain'e ekle, sonra tekrar çalıştır."
  echo "  (Şimdilik ad-hoc imzalı sürüm: ./tools/build-release.sh $VERSION)"
  exit 1
fi

echo "→ İmzalanıyor: $DEVELOPER_ID"
if [ ! -d "$APP" ]; then ./build.sh; fi

# İçten dışa imzalama (hardened runtime + zaman damgası)
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" \
  "$APP/Contents/Frameworks/libMCBUploadCore.dylib"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" \
  --entitlements "$ROOT/Resources/FinderSync.entitlements" \
  "$APP/Contents/PlugIns/UploadToFTPFinder.appex"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "→ Notarization paketi hazırlanıyor"
rm -rf "$DIST"
mkdir -p "$DIST"
ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"

echo "→ Apple'a gönderiliyor (birkaç dakika sürebilir)"
xcrun notarytool submit "$DIST/notarize.zip" --keychain-profile "$PROFILE" --wait

echo "→ Bilet uygulamaya yapıştırılıyor (staple)"
xcrun stapler staple "$APP"
rm -f "$DIST/notarize.zip"

echo "→ Dağıtım paketleri"
"$ROOT/tools/build-release.sh" "$VERSION"

echo ""
echo "✓ Notarize edilmiş sürüm hazır: $DIST"
spctl --assess --type execute --verbose=2 "$APP" || true
