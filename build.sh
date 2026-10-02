#!/bin/bash
# Builds dist/Sweepy.app. Usage: ./build.sh [--install]  (--install copies it to /Applications)
set -euo pipefail
cd "$(dirname "$0")"

# UNIVERSAL=1 builds for both Apple Silicon and Intel.
ARCH_FLAGS=()
[ "${UNIVERSAL:-0}" = "1" ] && ARCH_FLAGS=(--arch arm64 --arch x86_64)
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR=$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)

if [ ! -f Resources/AppIcon.icns ]; then
  ICONSET=$(mktemp -d)/AppIcon.iconset
  mkdir -p "$ICONSET"
  swift scripts/make-icon.swift "$ICONSET/base.png"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  rm "$ICONSET/base.png"
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi

APP=dist/Sweepy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Sweepy" "$APP/Contents/MacOS/Sweepy"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Đã build $APP"

if [ "${1:-}" = "--install" ]; then
  osascript -e 'quit app "Sweepy"' 2>/dev/null || true
  rm -rf /Applications/Sweepy.app
  cp -R "$APP" /Applications/Sweepy.app
  echo "Đã cài vào /Applications/Sweepy.app"
fi
