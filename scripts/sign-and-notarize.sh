#!/bin/bash
# Ký Developer ID + notarize dist/Sweepy.app. CI chỉ gọi khi có đủ secrets:
#   MACOS_CERT_P12 (base64 của file .p12), MACOS_CERT_PASSWORD,
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD (app-specific password)
set -euo pipefail
APP=dist/Sweepy.app

KEYCHAIN="$RUNNER_TEMP/sign.keychain-db"
KC_PASS=$(uuidgen)
echo "$MACOS_CERT_P12" | base64 --decode > "$RUNNER_TEMP/cert.p12"
security create-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
security import "$RUNNER_TEMP/cert.p12" -k "$KEYCHAIN" -P "$MACOS_CERT_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN" | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')
[ -n "$IDENTITY" ] || { echo "Không tìm thấy chứng chỉ Developer ID Application"; exit 1; }

codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

ditto -c -k --keepParent "$APP" "$RUNNER_TEMP/notarize.zip"
AUTH=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
SUBMISSION=$(xcrun notarytool submit "$RUNNER_TEMP/notarize.zip" "${AUTH[@]}" --output-format json \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
echo "Notary submission: $SUBMISSION"

# Apple can take a long time (especially the first submissions of a new team) and the runner's
# connection sometimes drops while polling, so keep waiting on the same submission instead of failing.
STATUS=""
for attempt in $(seq 1 12); do
  xcrun notarytool wait "$SUBMISSION" "${AUTH[@]}" --timeout 20m || true
  STATUS=$(xcrun notarytool info "$SUBMISSION" "${AUTH[@]}" --output-format json 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' || true)
  echo "Lần $attempt: $STATUS"
  [ "$STATUS" = "In Progress" ] || [ -z "$STATUS" ] || break
  sleep 30
done
if [ "$STATUS" != "Accepted" ]; then
  xcrun notarytool log "$SUBMISSION" "${AUTH[@]}" || true
  echo "Notarize không thành công: ${STATUS:-không rõ}"
  exit 1
fi
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"
