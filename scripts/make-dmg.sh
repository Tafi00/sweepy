#!/bin/bash
# Tạo dist/Sweepy.dmg: cửa sổ có Sweepy.app và lối tắt Applications để kéo-thả cài đặt.
#   ./scripts/make-dmg.sh ["Developer ID Application: …"]   (có identity thì ký luôn file dmg)
set -euo pipefail
cd "$(dirname "$0")/.."
APP=dist/Sweepy.app
DMG=dist/Sweepy.dmg
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/Sweepy.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Sweepy" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null

if [ -n "${1:-}" ]; then
  codesign --force --timestamp --sign "$1" "$DMG"
  codesign --verify --verbose=2 "$DMG"
fi
echo "Đã tạo $DMG ($(du -h "$DMG" | cut -f1))"
