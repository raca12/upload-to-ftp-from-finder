#!/bin/sh
# Finder sağ tık eklentisini kurar / yeniler (Xcode gerekmez).
# Kullanım: ./tools/install-extension.sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/bin/Upload to FTP from Finder.app"
TARGET="/Applications/Upload to FTP from Finder.app"
EXT_ID="com.mcb.upload.FinderSync"

if [ ! -d "$APP" ]; then
  echo "Önce ./build.sh çalıştır."
  exit 1
fi

echo "→ Eski Rightload kurulumu kaldırılıyor"
pluginkit -e ignore -i org.rightload.mac.FinderSync 2>/dev/null || true
rm -rf "/Applications/Rightload.app"

echo "→ /Applications'a kopyalanıyor (Finder eklentileri standart konum ister)"
rm -rf "$TARGET"
cp -R "$APP" "$TARGET"

echo "→ Ayarlar taşınıyor (varsa)"
LEGACY="$HOME/Library/Application Support/RightloadMac"
NEW="$HOME/Library/Application Support/MCBUpload"
if [ -d "$LEGACY" ] && [ ! -d "$NEW" ]; then
  mkdir -p "$NEW"
  cp -R "$LEGACY"/. "$NEW"/ 2>/dev/null || true
  echo "  eski ayarlar kopyalandı"
fi

echo "→ LaunchServices kaydı"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R "$TARGET"

echo "→ Eklenti kaydı"
pluginkit -a "$TARGET/Contents/PlugIns/UploadToFTPFinder.appex"
pluginkit -e use -i "$EXT_ID"

echo "→ Finder yeniden başlatılıyor"
killall Finder 2>/dev/null || true
sleep 2

echo ""
echo "Durum:"
pluginkit -m -i "$EXT_ID" -v || echo "  (eklenti görünmüyor — Sistem Ayarları > Genel > Oturum Açma Öğeleri > Uzantılar)"
echo ""
echo "✓ Kuruldu. Finder'da bir dosyaya SAĞ TIKLA → \"MCB Upload ile Yükle\"."
echo "  Eklenti görünmezse: Sistem Ayarları > Genel > Oturum Açma Öğeleri ve Uzantılar > Bulunan Öğeler > "Upload to FTP from Finder" açık hale getir."
echo "  Kaldırmak için: pluginkit -e ignore -i $EXT_ID && rm -rf $TARGET"
