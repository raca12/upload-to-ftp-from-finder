#!/bin/sh
# Developer ID + notarytool kurulum kontrolü ve notarized sürüm üretimi.
#
# Kullanım:
#   ./tools/setup-signing.sh [sürüm]
#
# Sertifika yoksa yapılacakları yazar.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.1}"
PROFILE="${NOTARY_PROFILE:-mcb-notary}"
TEAM_ID="${TEAM_ID:-}"

echo "1) Developer ID Application sertifikası kontrol ediliyor…"
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)"

if [ -z "$IDENTITY" ]; then
  cat <<'EOF'
✗ Developer ID Application sertifikası bulunamadı.

Bu Mac'te kurulum (Xcode gerekmez):

  a) Keychain Access → menü: Keychain Access › Certificate Assistant ›
     "Request a Certificate From a Certificate Authority…"
     · User Email Address: Apple Developer hesabın
     · Common Name: adın
     · "Saved to disk" seç → CertificateSigningRequest.certSigningRequest kaydet

  b) https://developer.apple.com/account/resources/certificates/list
     → + → "Developer ID Application" → CSR dosyasını yükle → indir (.cer)

  c) İndirdiğin .cer dosyasına çift tıkla (Keychain'e eklenir)

  d) Kontrol:
     security find-identity -v -p codesigning

  Sonra bu betiği tekrar çalıştır.
EOF
  exit 1
fi

echo "   ✓ $IDENTITY"

echo ""
echo "2) notarytool kimlik bilgileri kontrol ediliyor…"
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  cat <<EOF
   Profil yok: "$PROFILE"
   Aşağıdaki komutu SEN çalıştır (app-specific password'ü ben görmemeliyim):

     xcrun notarytool store-credentials "$PROFILE" \\
       --apple-id "APPLE_ID" --team-id "TEAM_ID" --password "APP_SPECIFIC_PASSWORD"

   · Team ID: https://developer.apple.com/account → Membership
   · App-specific password: https://appleid.apple.com → Sign-In and Security

   Sonra: ./tools/setup-signing.sh $VERSION
EOF
  exit 1
fi

echo "   ✓ notarytool profili hazır"
[ -n "$TEAM_ID" ] && export TEAM_ID

echo ""
echo "3) Notarized sürüm üretiliyor…"
DEVELOPER_ID="$IDENTITY" NOTARY_PROFILE="$PROFILE" "$ROOT/tools/notarize.sh" "$VERSION"
