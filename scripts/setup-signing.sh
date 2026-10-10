#!/bin/zsh
# Tek seferlik: MacHealth için kalıcı, yerel bir kod imzalama sertifikası oluşturur.
#
# Neden? Ad-hoc imzada (codesign -s -) her derlemenin kimliği farklı olur ve macOS verdiğin
# izinleri (Tam Disk Erişimi vb.) yeni derlemeye uygulamaz; her seferinde yeniden izin istersin.
# Sabit bir sertifikayla imzalanan uygulamayı macOS güncellemeler arasında aynı uygulama sayar.
#
# Kullanım: ./scripts/setup-signing.sh   (macOS bir kez şifreni sorar: sertifikaya güvenmek için)
set -euo pipefail

NAME="MacHealth Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "✓ \"$NAME\" zaten kurulu."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=$(uuidgen)

cat > "$TMP/cs.cnf" <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF

echo "› Sertifika oluşturuluyor…"
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cs.cnf" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout "pass:$PASS" -name "$NAME"

echo "› Anahtar zincirine ekleniyor…"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "› Kod imzalama için güveniliyor (macOS şifreni sorabilir)…"
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "✓ Hazır. Şimdi ./scripts/build-app.sh ile derle; Tam Disk Erişimi'ni bir kez ver, sonraki derlemelerde kalır."
else
  echo "✗ Sertifika eklendi ama geçerli görünmüyor. Anahtar Zinciri Erişimi'nde \"$NAME\" sertifikasını açıp"
  echo "  Güven › Kod İmzalama: Her Zaman Güven olarak ayarla."
  exit 1
fi
