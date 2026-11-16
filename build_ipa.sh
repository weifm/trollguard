#!/bin/bash
# TrollGuard 一键打包脚本（在 macOS 上运行，GitHub Actions 的 macos runner 也可）
# 产物：TrollGuard.tipa —— 用巨魔商店直接安装
set -euo pipefail

APP_NAME="TrollGuard"
BUILD_DIR="build"

echo "==> [1/5] 生成 Xcode 工程 (xcodegen)"
xcodegen generate

echo "==> [2/5] 编译 (iPhoneOS / Release / 免签名)"
xcodebuild -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -derivedDataPath "${BUILD_DIR}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    build

APP="${BUILD_DIR}/Build/Products/Release-iphoneos/${APP_NAME}.app"
if [ ! -d "${APP}" ]; then
  echo "❌ 未找到产物目录：${APP}"
  exit 1
fi

echo "==> [3/5] ldid 注入巨魔 entitlements"
ldid -SEntitlements/App.plist           "${APP}/${APP_NAME}"
ldid -SEntitlements/CallDirectory.plist "${APP}/PlugIns/CallDirectoryExtension.appex/CallDirectoryExtension"
ldid -SEntitlements/MessageFilter.plist "${APP}/PlugIns/MessageFilterExtension.appex/MessageFilterExtension"

echo "==> [4/5] 校验签名"
ldid -e "${APP}/${APP_NAME}" | head -5

echo "==> [5/5] 打包 .tipa"
rm -rf Payload "${APP_NAME}.tipa"
mkdir -p Payload
cp -R "${APP}" Payload/
zip -qry "${APP_NAME}.tipa" Payload
rm -rf Payload

echo ""
echo "完成 ✅ 产物：${APP_NAME}.tipa"
echo "传到 iPhone（AirDrop / 网盘 / 微信文件传输），用巨魔商店打开安装。"
