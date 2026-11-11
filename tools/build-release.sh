#!/bin/sh
# Sürüm paketi üretir: dist/ içinde DMG + ZIP + SHA256.
# Kullanım: ./tools/build-release.sh [sürüm]
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
APP_NAME="Upload to FTP from Finder"
APP="$ROOT/bin/$APP_NAME.app"
DIST="$ROOT/dist"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

if [ ! -d "$APP" ]; then
  echo "→ Önce ./build.sh çalıştırılıyor"
  "$ROOT/build.sh"
fi

echo "→ Paketleniyor (v$VERSION)"
rm -rf "$DIST"
mkdir -p "$DIST"

# --- ZIP: uygulama + CLI ---
ZIP_STAGE="$STAGE/zip"
mkdir -p "$ZIP_STAGE"
cp -R "$APP" "$ZIP_STAGE/"
cp "$ROOT/bin/mcb" "$ZIP_STAGE/"
cp "$ROOT/LICENSE" "$ZIP_STAGE/" 2>/dev/null || true
ditto -c -k --sequesterRsrc "$ZIP_STAGE" "$DIST/UploadToFTP-$VERSION.zip"

# --- DMG: uygulama + Applications kısayolu ---
DMG_STAGE="$STAGE/dmg"
mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$DMG_STAGE" \
  -fs HFS+ -format UDZO -ov "$DIST/UploadToFTP-$VERSION.dmg"

# --- Sağlama toplamları ---
(
  cd "$DIST"
  shasum -a 256 "UploadToFTP-$VERSION.dmg" "UploadToFTP-$VERSION.zip" > SHA256SUMS.txt
)

echo ""
echo "✓ dist/"
ls -lh "$DIST"
echo ""
cat "$DIST/SHA256SUMS.txt"
