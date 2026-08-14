#!/bin/bash
# RHEO Mac 一鍵發版：簽名 → 公證 → staple → DMG → 簽名 → 公證 → staple → quarantine 驗收 → 蓋 release/
# 照抄 ALIGNED scripts/release-mac.sh（源頭是 STB 跑過六個版本的流程），差異：
#   - 無內嵌 sidecar binary，只簽 .app 本體
#   - xcodebuild 的 Release 建置帶 get-task-allow（automatic 簽名預設注入），公證必退件
#     → 重簽時用空 entitlements 蓋掉
#   - 不上傳 GitHub Release（先不發表，DMG 只落地 release/）
# 用法：scripts/release-mac.sh [RHEO.app 路徑]
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-/tmp/rheo-mac-rel/Build/Products/Release/RHEO.app}"
ID="Developer ID Application: WEI-MING KAO (GHCWJ24V46)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

[ -d "$APP" ] || { echo "❌ 找不到 ${APP}（先 xcodebuild -configuration Release build）"; exit 1; }
VER=$(defaults read "$(cd "$APP" && pwd)/Contents/Info.plist" CFBundleShortVersionString)
mkdir -p release
DMG="release/RHEO_${VER}_aarch64.dmg"
echo "▸ 發版 v${VER}（來源：${APP}）"

# 公證認證走 .p8 直連（鑰匙圈 profile 會無預警讀不到，.p8 在 headless／排程下也穩）
NOTARY_AUTH=(--key "$HOME/.appstoreconnect/private_keys/AuthKey_J63NP838KQ.p8"
             --key-id J63NP838KQ --issuer f1386394-19c4-4163-aa40-504dac653053)
notarize() {
  xcrun notarytool submit "$1" "${NOTARY_AUTH[@]}" --wait 2>&1 | tail -3 \
    | grep -q "Accepted" || { echo "❌ 公證失敗：${1}（xcrun notarytool log 查詳情）"; exit 1; }
}

echo "▸ 簽名（hardened runtime，空 entitlements 蓋掉 get-task-allow）"
ditto "$APP" "$WORK/RHEO.app"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict/></plist>\n' > "$WORK/empty.entitlements"
codesign --force --options runtime --timestamp --entitlements "$WORK/empty.entitlements" -s "$ID" "$WORK/RHEO.app"

echo "▸ 公證 app（幾分鐘）"
ditto -c -k --keepParent "$WORK/RHEO.app" "$WORK/app.zip"
notarize "$WORK/app.zip"
xcrun stapler staple -q "$WORK/RHEO.app"

echo "▸ 打 DMG（手動 hdiutil）＋簽名"
mkdir "$WORK/root"
ditto "$WORK/RHEO.app" "$WORK/root/RHEO.app"
ln -s /Applications "$WORK/root/Applications"
hdiutil create -volname "RHEO" -srcfolder "$WORK/root" -ov -format UDZO "$WORK/out.dmg" -quiet
codesign --force --timestamp -s "$ID" "$WORK/out.dmg"

echo "▸ 公證 DMG（幾分鐘）"
notarize "$WORK/out.dmg"
xcrun stapler staple -q "$WORK/out.dmg"

echo "▸ quarantine 模擬驗收"
xattr -w com.apple.quarantine "0083;0;Safari;RELEASE-TEST" "$WORK/out.dmg"
spctl -a -t open --context context:primary-signature "$WORK/out.dmg" >/dev/null 2>&1 \
  || { echo "❌ DMG spctl 未過"; exit 1; }
hdiutil attach -nobrowse -readonly "$WORK/out.dmg" -mountpoint "$WORK/mnt" -quiet
ditto "$WORK/mnt/RHEO.app" "$WORK/qapp"
hdiutil detach "$WORK/mnt" -quiet
xattr -w com.apple.quarantine "0083;0;Safari;RELEASE-TEST" "$WORK/qapp"
spctl -a -t exec -vv "$WORK/qapp" 2>&1 | grep -q "Notarized Developer ID" \
  || { echo "❌ app spctl 未過"; exit 1; }

cp "$WORK/out.dmg" "$DMG"
echo "✅ v${VER} 全綠，已蓋 ${DMG}（SHA $(shasum -a 256 "$DMG" | cut -c1-8)…）"
