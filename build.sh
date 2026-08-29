#!/bin/bash
# QQPlayer iOS 原生版一键构建
# 用法:
#   ./build.sh              模拟器构建（免签名，iPhone 17 Pro）
#   ./build.sh --install    真机签名构建 + devicectl 安装 + 启动（需连接 iPhone，team B6FA37AYT5）
set -euo pipefail
cd "$(dirname "$0")"

DERIVED="build/DerivedData"
SCHEME="QQPlayer"   # scheme 名
APP_NAME="QQPlayer" # 可执行/产物名

# 探测已连接真机（devicectl JSON 输出 → python 提取 connected 设备，避免 awk $() 歧义）
detect_udid() {
  local OUT="/tmp/qqplayer-devices.json"
  xcrun devicectl list devices --json-output "${OUT}" >/dev/null 2>&1 || return 1
  python3 -c '
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
for d in data.get("result", {}).get("devices", []):
    conn = d.get("connectionProperties", {})
    hw = d.get("hardwareProperties", {})
    if conn.get("tunnelState") == "connected" and hw.get("udid"):
        print(hw["udid"])
        sys.exit(0)
sys.exit(1)
' "${OUT}"
}

build_sim() {
  echo "=== 模拟器构建 ==="
  xcodebuild -project "QQPlayer.xcodeproj" -scheme "${SCHEME}" \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -derivedDataPath "${DERIVED}" build
}

build_install() {
  local UDID
  UDID="$(detect_udid || true)"
  if [ -z "${UDID}" ]; then
    echo "❌ 未发现已连接的真机（请用数据线连接 iPhone 并信任此 Mac）"
    exit 1
  fi
  echo "=== 真机构建（UDID=${UDID}） ==="
  xcodebuild -project "QQPlayer.xcodeproj" -scheme "${SCHEME}" \
    -destination "id=${UDID}" -derivedDataPath "${DERIVED}" \
    -allowProvisioningUpdates build
  local APP
  APP="${DERIVED}/Build/Products/Debug-iphoneos/${APP_NAME}.app"
  echo "=== 安装到真机 ==="
  xcrun devicectl device install app --device "${UDID}" "${APP}"
  echo "=== 启动 ==="
  xcrun devicectl device process launch --device "${UDID}" com.daxmate.qqplayer.ios
}

case "${1:-}" in
  --install) build_install ;;
  *) build_sim ;;
esac
echo "✅ 完成"
