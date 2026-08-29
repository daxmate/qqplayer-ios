#!/bin/bash
# QQPlayer iOS 原生版一键构建
# 用法:
#   ./build.sh              模拟器构建（免签名，iPhone 17 Pro）
#   ./build.sh --install    真机签名构建 + devicectl 安装 + 启动（需连接 iPhone，team B6FA37AYT5）
set -euo pipefail
cd "$(dirname "$0")"

DERIVED="build/DerivedData"
SCHEME="Cosmos Music Player"   # scheme 名（工程名沿用 Cosmos，显示名已是 QQPlayer）
APP_NAME="Cosmos Music Player" # 可执行/产物名（未改 PRODUCT_NAME，安装后显示 QQPlayer）

build_sim() {
  echo "=== 模拟器构建 ==="
  xcodebuild -project "Cosmos Music Player.xcodeproj" -scheme "$SCHEME" \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -derivedDataPath "$DERIVED" build
}

build_install() {
  UDID=$(xcrun devicectl list devices 2>/dev/null | awk '{
    for (i = 1; i <= NF; i++)
      if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/ && $(i+1) == "connected") { print $i; exit }
  }')
  if [ -z "$UDID" ]; then
    echo "❌ 未发现已连接的真机（请用数据线连接 iPhone 并信任此 Mac）"
    exit 1
  fi
  echo "=== 真机构建（UDID=$UDID） ==="
  xcodebuild -project "Cosmos Music Player.xcodeproj" -scheme "$SCHEME" \
    -destination "id=$UDID" -derivedDataPath "$DERIVED" build
  APP="$DERIVED/Build/Products/Debug-iphoneos/$APP_NAME.app"
  echo "=== 安装到真机 ==="
  xcrun devicectl device install app --device "$UDID" "$APP"
  echo "=== 启动 ==="
  xcrun devicectl device process launch --device "$UDID" com.daxmate.qqplayer.ios
}

case "${1:-}" in
  --install) build_install ;;
  *) build_sim ;;
esac
echo "✅ 完成"
