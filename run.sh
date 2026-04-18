#!/bin/bash
# 构建并（重新）启动 MacosMonitor.app
set -euo pipefail
cd "$(dirname "$0")"

APP="MacosMonitor.app"

# 确保 .app bundle 目录结构存在（首次 clone 后 MacOS/ 和 Resources/ 为空）
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"

# 图标缺失就生成
if [ ! -f "${APP}/Contents/Resources/AppIcon.icns" ]; then
    echo "==> generating app icon"
    swift tools/generate_icon.swift AppIcon.iconset
    iconutil -c icns AppIcon.iconset -o "${APP}/Contents/Resources/AppIcon.icns"
    rm -rf AppIcon.iconset
fi

swift build -c release
cp .build/release/MacosMonitor "${APP}/Contents/MacOS/MacosMonitor"

pkill -x MacosMonitor 2>/dev/null || true
sleep 0.3
open "${APP}"
echo "Launched ${APP} (pid=$(pgrep -x MacosMonitor | tr '\n' ' '))"
