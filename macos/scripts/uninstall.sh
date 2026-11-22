#!/usr/bin/env bash
set -euo pipefail

HOST_NAME="com.muyuchen.mactimer.host"
SUPPORT_DIR="$HOME/Library/Application Support/MacTimer"
HOST_BIN="$SUPPORT_DIR/bin/MacTimerHost"
MANIFEST_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
MANIFEST_PATH="$MANIFEST_DIR/$HOST_NAME.json"

# Previous release names.
LEGACY_SUPPORT_DIR="$HOME/Library/Application Support/StayTimer"
LEGACY_HOST_BIN="$LEGACY_SUPPORT_DIR/bin/StayTimerHost"
LEGACY_MANIFEST_PATH="$MANIFEST_DIR/com.muyuchen.staytimer.host.json"

# The app may live in either Applications folder, under either name.
rm -rf "/Applications/MacTimer.app" "$HOME/Applications/MacTimer.app" \
    "/Applications/StayTimer.app" "$HOME/Applications/StayTimer.app"
rm -f "$HOST_BIN" "$LEGACY_HOST_BIN"
rm -f "$MANIFEST_PATH" "$LEGACY_MANIFEST_PATH"

if [[ "${1:-}" == "--purge" ]]; then
    rm -rf "$SUPPORT_DIR" "$LEGACY_SUPPORT_DIR"
    echo "已移除 App、本地桥、Chrome 清单和全部本地数据。"
else
    echo "已移除 App、本地桥和 Chrome 清单。"
    echo "数据仍保留在：$SUPPORT_DIR"
    echo "旧版数据目录（如果有）：$LEGACY_SUPPORT_DIR"
    echo "需要一并删除时运行：$0 --purge"
fi
echo
echo "如果之前在「完全磁盘访问权限」中添加过 MacTimer/StayTimer，建议在系统设置中一并移除。"

