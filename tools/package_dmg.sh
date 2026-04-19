#!/bin/bash
# 打包 Orbit.app 为可分发的 DMG。
# 产物：Orbit.dmg（挂载后拖到 Applications 即安装）。
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Orbit"
VOL_NAME="Orbit"
STAGING=".dmg-staging"
DMG_OUT="${APP_NAME}.dmg"
APP="${APP_NAME}.app"

mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

# 图标缺失就生成
if [ ! -f "${APP}/Contents/Resources/AppIcon.icns" ]; then
    echo "==> generating app icon"
    swift tools/generate_icon.swift AppIcon.iconset
    iconutil -c icns AppIcon.iconset -o "${APP}/Contents/Resources/AppIcon.icns"
    rm -rf AppIcon.iconset
fi

echo "==> swift build -c release"
swift build -c release
cp .build/release/${APP_NAME} ${APP}/Contents/MacOS/${APP_NAME}

echo "==> staging ${STAGING}/"
rm -rf "${STAGING}"
mkdir -p "${STAGING}"
cp -R ${APP} "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

echo "==> hdiutil create ${DMG_OUT}"
rm -f "${DMG_OUT}"
hdiutil create \
    -volname "${VOL_NAME}" \
    -srcfolder "${STAGING}" \
    -ov \
    -format UDZO \
    "${DMG_OUT}" >/dev/null

rm -rf "${STAGING}"

echo ""
echo "✓ Created: $(pwd)/${DMG_OUT}"
echo "  Size:    $(du -h ${DMG_OUT} | cut -f1)"
