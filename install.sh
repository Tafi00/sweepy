#!/bin/bash
# Cài Sweepy bản mới nhất từ GitHub Releases.
#   curl -fsSL https://raw.githubusercontent.com/Tafi00/sweepy/main/install.sh | bash
# Tải bằng curl nên file không bị gắn cờ quarantine → Gatekeeper không chặn.
set -euo pipefail

REPO="Tafi00/sweepy"
URL="https://github.com/$REPO/releases/latest/download/Sweepy.zip"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "→ Đang tải Sweepy…"
curl -fL --progress-bar "$URL" -o "$TMP/Sweepy.zip"
ditto -x -k "$TMP/Sweepy.zip" "$TMP"

DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

osascript -e 'quit app "Sweepy"' >/dev/null 2>&1 || true
rm -rf "$DEST/Sweepy.app"
mv "$TMP/Sweepy.app" "$DEST/Sweepy.app"
# Phòng trường hợp file đi qua đường khác có gắn cờ.
xattr -dr com.apple.quarantine "$DEST/Sweepy.app" 2>/dev/null || true

echo "✓ Đã cài vào $DEST/Sweepy.app"
open "$DEST/Sweepy.app"
