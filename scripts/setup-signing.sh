#!/bin/bash
# Đưa chứng chỉ Developer ID + thông tin notarize vào GitHub Secrets của repo.
# Mọi giá trị nhạy cảm chỉ được gõ vào terminal này và gửi thẳng lên GitHub (mã hoá), không lưu ra đĩa.
#   ./scripts/setup-signing.sh ~/Desktop/DeveloperID.p12
set -euo pipefail

REPO="${REPO:-Tafi00/sweepy}"
P12="${1:-}"
if [ -z "$P12" ] || [ ! -f "$P12" ]; then
  echo "Cách dùng: $0 <đường-dẫn-file.p12>"
  echo "Xuất file .p12: Keychain Access → My Certificates → chuột phải \"Developer ID Application: …\" → Export."
  exit 1
fi

read -r -s -p "Mật khẩu của file .p12: " P12_PASS; echo

# Kiểm tra file đúng là Developer ID Application và lấy Team ID.
export P12_PASS
SUBJECT=$(openssl pkcs12 -in "$P12" -nokeys -passin env:P12_PASS 2>/dev/null || openssl pkcs12 -legacy -in "$P12" -nokeys -passin env:P12_PASS 2>/dev/null || true)
if ! grep -q "Developer ID Application" <<<"$SUBJECT"; then
  echo "✗ File này không chứa chứng chỉ Developer ID Application (hoặc sai mật khẩu)."; exit 1
fi
NAME=$(grep -o "Developer ID Application: [^/,]*([A-Z0-9]\{10\})" <<<"$SUBJECT" | head -1)
TEAM_ID=$(sed -E 's/.*\(([A-Z0-9]{10})\)$/\1/' <<<"$NAME")
echo "✓ Chứng chỉ: $NAME"

read -r -p "Apple ID (email tài khoản developer): " APPLE_ID
read -r -s -p "App-specific password (tạo ở account.apple.com → Sign-In and Security): " APP_PASS; echo

echo "→ Kiểm tra thông tin notarize với Apple…"
if ! xcrun notarytool history --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASS" >/dev/null 2>&1; then
  echo "✗ Apple từ chối Apple ID / app-specific password / Team ID $TEAM_ID."; exit 1
fi
echo "✓ Thông tin notarize hợp lệ"

base64 -i "$P12" | gh secret set MACOS_CERT_P12 --repo "$REPO"
printf '%s' "$P12_PASS" | gh secret set MACOS_CERT_PASSWORD --repo "$REPO"
printf '%s' "$APPLE_ID" | gh secret set APPLE_ID --repo "$REPO"
printf '%s' "$TEAM_ID" | gh secret set APPLE_TEAM_ID --repo "$REPO"
printf '%s' "$APP_PASS" | gh secret set APPLE_APP_PASSWORD --repo "$REPO"
unset P12_PASS APP_PASS
echo "✓ Đã lưu 5 secret vào $REPO"
echo "Bản phát hành tiếp theo (git tag v… && git push --tags) sẽ được ký và notarize."
