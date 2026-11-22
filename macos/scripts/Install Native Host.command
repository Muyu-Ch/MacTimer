#!/usr/bin/env bash
set -euo pipefail

# This helper is included in the release DMG. It installs a stable copy of
# the unpacked extension, the native messaging host, and the Chrome manifest.
# The extension ID for an unpacked Chrome extension is derived from its
# absolute path, so keeping the stable copy at the same path lets the host
# manifest stay valid across updates.

HOST_NAME="com.muyuchen.mactimer.host"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SUPPORT_DIR="${MACTIMER_SUPPORT_DIR:-$HOME/Library/Application Support/MacTimer}"
CHROME_MANIFEST_DIR="${MACTIMER_CHROME_MANIFEST_DIR:-$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts}"
HOST_SOURCE="${MACTIMER_HOST_BINARY:-$SCRIPT_DIR/MacTimerHost}"
HOST_BIN="$SUPPORT_DIR/bin/MacTimerHost"
EXT_DEST="$SUPPORT_DIR/Extension"
EXT_SOURCE="${1:-}"

pause_if_terminal() {
    if [[ -t 0 ]]; then
        read -r -n 1 -s -p "按任意键关闭..." || true
        echo
    fi
}

fail() {
    echo "错误：$1" >&2
    pause_if_terminal
    exit 1
}

if [[ -z "$EXT_SOURCE" ]]; then
    EXT_SOURCE="$(osascript <<'APPLESCRIPT'
try
    set selectedFolder to choose folder with prompt "选择解压后的 MacTimer 扩展目录（包含 manifest.json 的目录）"
    return POSIX path of selectedFolder
on error number -128
    return ""
end try
APPLESCRIPT
)"
fi
EXT_SOURCE="${EXT_SOURCE%/}"

if [[ -z "$EXT_SOURCE" ]]; then
    echo "已取消。"
    exit 1
fi
if [[ ! -f "$EXT_SOURCE/manifest.json" ]]; then
    fail "所选目录里没有 manifest.json。请选择解压后包含 manifest.json 的扩展目录本身。"
fi
if [[ ! -f "$HOST_SOURCE" ]]; then
    fail "找不到 MacTimerHost。请在 MacTimer 的 DMG 内运行此脚本。"
fi

echo
echo "MacTimer 本地桥安装程序"
echo "----------------------------------------"
echo "扩展来源：$EXT_SOURCE"
echo "扩展目标：$EXT_DEST"
echo

mkdir -p "$SUPPORT_DIR/bin" "$CHROME_MANIFEST_DIR"

# Copy through a temporary directory so re-running this helper while the
# source is already the stable copy cannot delete the source mid-copy.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
ditto "$EXT_SOURCE" "$TMP_DIR/Extension"
rm -rf "$EXT_DEST"
ditto "$TMP_DIR/Extension" "$EXT_DEST"

EXT_DEST_REAL="$(cd "$EXT_DEST" && pwd -P)"
cp "$HOST_SOURCE" "$HOST_BIN"
chmod 755 "$HOST_BIN"
xattr -dr com.apple.quarantine "$HOST_BIN" "$EXT_DEST" >/dev/null 2>&1 || true
if ! codesign --force --sign - "$HOST_BIN" >/dev/null 2>&1; then
    echo "提示：本地桥 ad-hoc 签名失败，但通常仍可由 Chrome 启动。"
fi

EXT_ID="$(printf '%s' "$EXT_DEST_REAL" | shasum -a 256 | cut -c1-32 | tr '0-9a-f' 'a-p')"
if [[ ${#EXT_ID} -ne 32 ]]; then
    fail "无法计算扩展 ID。"
fi

cat > "$CHROME_MANIFEST_DIR/$HOST_NAME.json" <<EOF
{
  "name": "$HOST_NAME",
  "description": "MacTimer local data bridge",
  "path": "$HOST_BIN",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$EXT_ID/"]
}
EOF

echo
echo "安装完成。"
echo
echo "扩展稳定目录："
echo "  $EXT_DEST_REAL"
echo
echo "扩展 ID：$EXT_ID"
echo "本地桥：$HOST_BIN"
echo "Chrome 清单：$CHROME_MANIFEST_DIR/$HOST_NAME.json"
echo
echo "下一步："
echo "  1. 打开 Chrome，进入 chrome://extensions"
echo "  2. 打开右上角「开发者模式」"
echo "  3. 点击「加载已解压的扩展程序」"
echo "  4. 选择上面的扩展稳定目录"
echo "  5. 如果之前加载过旧版 MacTimer，先移除旧扩展，避免重复"
echo "  6. 点击扩展图标，在弹窗底部点「同步到 Mac」"
echo
echo "Mac App 首次使用还需要在："
echo "  系统设置 → 隐私与安全性 → 完全磁盘访问权限"
echo "中添加 /Applications/MacTimer.app。"
echo
pause_if_terminal
