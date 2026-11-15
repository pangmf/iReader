#!/usr/bin/env bash
#
# 一键打包 ipa
#
#   有开发者账号（自动签名）：
#     TEAM_ID=ABCDE12345 ./build_ipa.sh
#
#   无账号（产出未签名 ipa，可用 TrollStore / AltStore / Sideloadly 自签安装）：
#     ./build_ipa.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

SCHEME="WeReadLike"
APP_NAME="iReader"
PROJECT="WeReadLike.xcodeproj"
CONFIG="Release"
OUT="$ROOT/build"
TEAM_ID="${TEAM_ID:-}"

command -v xcodebuild >/dev/null 2>&1 || {
  echo "✗ 找不到 xcodebuild，请在 macOS 上安装 Xcode 后运行。"
  exit 1
}

rm -rf "$OUT"
mkdir -p "$OUT"

ARCHIVE="$OUT/$SCHEME.xcarchive"

if [[ -n "$TEAM_ID" ]]; then
  echo "==> 归档（自动签名，Team: $TEAM_ID）"
  xcodebuild -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    archive

  echo "==> 导出已签名 ipa"
  cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
PLIST

  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$OUT/ipa" \
    -exportOptionsPlist "$OUT/ExportOptions.plist"

  echo ""
  echo "✓ 完成：$OUT/ipa/$APP_NAME.ipa"
  echo "  用 Xcode → Window → Devices 拖入安装，或使用 Apple Configurator。"
  exit 0
fi

echo "==> 归档（不签名）"
xcodebuild -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  archive

echo "==> 组装未签名 ipa"
APP="$ARCHIVE/Products/Applications/$APP_NAME.app"
mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/"
rm -rf "$OUT/Payload/$APP_NAME.app/_CodeSignature"

(cd "$OUT" && zip -qry "$APP_NAME-unsigned.ipa" Payload)
rm -rf "$OUT/Payload"

echo ""
echo "✓ 完成：$OUT/$APP_NAME-unsigned.ipa"
echo "  安装方式（任选）："
echo "   · TrollStore（需对应系统版本）直接安装"
echo "   · Sideloadly / AltStore / Esign 自签后安装"
echo "   · macOS：Apple Configurator 2 拖入（会提示需要签名）"
