#!/bin/sh
# Upload to FTP from Finder — Xcode gerektirmeyen derleme betiği (Command Line Tools yeterli)
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/.build/manual"
LIB="$BUILD/lib"
MOD="$BUILD/modules"
BIN="$ROOT/bin"
APPEX_ID="com.mcb.upload.FinderSync"

mkdir -p "$LIB" "$MOD" "$BIN"

ARCH="$(uname -m)"
TARGET="$ARCH-apple-macos13.0"
SWIFT_FLAGS="-O -swift-version 5 -target $TARGET -I $MOD"

echo "→ MCBUploadCore derleniyor ($TARGET)"
# shellcheck disable=SC2046
swiftc $SWIFT_FLAGS -parse-as-library \
  -module-name MCBUploadCore \
  -emit-module -emit-module-path "$MOD/MCBUploadCore.swiftmodule" \
  -emit-library -o "$LIB/libMCBUploadCore.dylib" \
  -Xlinker -install_name -Xlinker "@rpath/libMCBUploadCore.dylib" \
  $(find "$ROOT/Sources/MCBUploadCore" -name '*.swift')

echo "→ mcb (CLI) derleniyor"
# shellcheck disable=SC2086
swiftc $SWIFT_FLAGS -module-name mcb \
  -L "$LIB" -lMCBUploadCore \
  -Xlinker -rpath -Xlinker "$LIB" \
  -o "$BIN/mcb" \
  "$ROOT/Sources/mcb/main.swift"

if [ "${1:-}" = "--with-selftest" ]; then
  echo "→ self-test derleniyor"
  # shellcheck disable=SC2086
  swiftc $SWIFT_FLAGS -module-name mcb_selftest \
    -L "$LIB" -lMCBUploadCore \
    -Xlinker -rpath -Xlinker "$LIB" \
    -o "$BUILD/selftest" \
    "$ROOT/Sources/selftest/main.swift"
fi

echo "→ GUI derleniyor"
# shellcheck disable=SC2086
swiftc $SWIFT_FLAGS -module-name MCBUploadApp \
  -L "$LIB" -lMCBUploadCore \
  -Xlinker -rpath -Xlinker "$LIB" \
  -o "$BUILD/UploadToFTPBin" \
  $(find "$ROOT/Sources/MCBUploadApp" -name '*.swift')

echo "→ Finder Sync eklentisi derleniyor"
clang -x objective-c -fobjc-arc -c -target "$TARGET" -o "$BUILD/appex-main.o" "$ROOT/Sources/MCBUploadFinderSync/main.m"
# shellcheck disable=SC2086
swiftc $SWIFT_FLAGS -parse-as-library -module-name MCBUploadFinderSync \
  -L "$LIB" -lMCBUploadCore \
  -Xlinker -rpath -Xlinker "@executable_path/../../../../Frameworks" \
  -o "$BUILD/UploadToFTPFinder" \
  $(find "$ROOT/Sources/MCBUploadFinderSync" -name '*.swift') \
  "$BUILD/appex-main.o" 

APP="$BIN/Upload to FTP from Finder.app"
APPEX="$APP/Contents/PlugIns/UploadToFTPFinder.appex"

echo "→ Uygulama paketi hazırlanıyor"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" \
         "$APPEX/Contents/MacOS"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BUILD/UploadToFTPBin" "$APP/Contents/MacOS/UploadToFTP"
cp "$LIB/libMCBUploadCore.dylib" "$APP/Contents/Frameworks/"
install_name_tool -change "@rpath/libMCBUploadCore.dylib" \
  "@executable_path/../Frameworks/libMCBUploadCore.dylib" \
  "$APP/Contents/MacOS/UploadToFTP" 2>/dev/null || true

cp "$ROOT/Resources/FinderSync-Info.plist" "$APPEX/Contents/Info.plist"
cp "$BUILD/UploadToFTPFinder" "$APPEX/Contents/MacOS/UploadToFTPFinder"

echo "→ İmzalanıyor (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP/Contents/Frameworks/libMCBUploadCore.dylib" >/dev/null 2>&1
codesign --force --sign - --timestamp=none \
  --entitlements "$ROOT/Resources/FinderSync.entitlements" \
  "$APPEX" >/dev/null 2>&1 || echo "  (appex imzalanamadı)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || echo "  (uygulama imzalanamadı)"

echo "✓ tamam"
echo "  CLI      : $BIN/mcb"
echo "  Uygulama : $APP"
echo "  Eklenti  : $APPEX ($APPEX_ID)"
