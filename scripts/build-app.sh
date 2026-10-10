#!/bin/zsh
# MacHealth.app paketini üretir: ./scripts/build-app.sh  (çıktı: build/MacHealth.app)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
APP="$ROOT/build/MacHealth.app"
VERSION="0.5.0"
SIGN_NAME="MacHealth Local Signing"

echo "› Derleniyor (release)…"
swift build -c release --arch arm64

echo "› Paketleniyor…"
rm -rf "$APP" "$ROOT/build/Cleaner.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/MacHealth" "$APP/Contents/MacOS/MacHealth"
# Hata ayıklama bilgisini at: derleyici kaynak dosyaların tam yolunu (/Users/<kullanıcı>/…) içine yazar.
strip -S -x "$APP/Contents/MacOS/MacHealth"

echo "› İkon üretiliyor (LogoMark)…"
TMP=$(mktemp -d)
"$APP/Contents/MacOS/MacHealth" --render-icon "$TMP/AppIcon.iconset" >/dev/null 2>&1 || true
if [[ -f "$TMP/AppIcon.iconset/icon_512x512@2x.png" ]]; then
  iconutil -c icns "$TMP/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
  cp "$TMP/AppIcon.iconset/icon_512x512@2x.png" "$ROOT/Resources/Logo.png"
elif [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  swift "$ROOT/scripts/make-icon.swift" "$TMP/AppIcon.iconset"
  iconutil -c icns "$TMP/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
fi
rm -rf "$TMP"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MacHealth</string>
  <key>CFBundleDisplayName</key><string>MacHealth</string>
  <key>CFBundleIdentifier</key><string>com.a0pia.machealth</string>
  <key>CFBundleExecutable</key><string>MacHealth</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>tr</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>MacHealth, yönetici gerektiren bakım görevleri ve yeniden başlatma için izin ister.</string>
</dict>
</plist>
PLIST

# Sabit sertifika varsa onunla imzala: macOS izinleri (Tam Disk Erişimi) yeni derlemelerde de geçerli kalır.
# Yoksa ad-hoc imza: her derlemede izinler sıfırlanır. Kurulum: ./scripts/setup-signing.sh
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$SIGN_NAME\""; then
  echo "› İmzalanıyor ($SIGN_NAME)…"
  codesign --force --deep --sign "$SIGN_NAME" "$APP"
else
  echo "› İmzalanıyor (ad-hoc)…"
  echo "  ! Her derlemede macOS izinleri sıfırlanır. Kalıcı olması için bir kez: ./scripts/setup-signing.sh"
  codesign --force --deep --sign - "$APP"
fi

# macOS ikon önbelleği aynı konumdaki uygulamanın eski ikonunu göstermeye devam edebilir.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$APP" >/dev/null 2>&1 || true

echo "✓ Hazır: $APP"
