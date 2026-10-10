#!/bin/zsh
# build/MacHealth.app'ten sürükle-bırak kurulumlu DMG üretir: ./scripts/make-dmg.sh  (çıktı: build/MacHealth-<sürüm>.dmg)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
APP="$ROOT/build/MacHealth.app"
[[ -d "$APP" ]] || ./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$ROOT/build/MacHealth-$VERSION.dmg"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "MacHealth" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "✓ Hazır: $DMG"
