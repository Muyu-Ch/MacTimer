#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST_NAME="com.muyuchen.mactimer.host"
SUPPORT_DIR="$HOME/Library/Application Support/MacTimer"
HOST_BIN="$SUPPORT_DIR/bin/MacTimerHost"
CHROME_SUPPORT="$HOME/Library/Application Support/Google/Chrome"
MANIFEST_DIR="$CHROME_SUPPORT/NativeMessagingHosts"
MANIFEST_PATH="$MANIFEST_DIR/$HOST_NAME.json"
SYSTEM_APP="/Applications/MacTimer.app"
HOME_APP="$HOME/Applications/MacTimer.app"
APP_INSTALL="${APP_INSTALL_PATH:-}"

# Previous release names. Keep the literals so upgrading users get their
# data copied and the old app/bridge entries removed.
LEGACY_HOST_NAME="com.muyuchen.staytimer.host"
LEGACY_SUPPORT_DIR="$HOME/Library/Application Support/StayTimer"
LEGACY_HOST_BIN="$LEGACY_SUPPORT_DIR/bin/StayTimerHost"
LEGACY_MANIFEST_PATH="$MANIFEST_DIR/$LEGACY_HOST_NAME.json"
LEGACY_SYSTEM_APP="/Applications/StayTimer.app"
LEGACY_HOME_APP="$HOME/Applications/StayTimer.app"

# Prefer the copy the user already has in /Applications. Falls back to the
# per-user Applications folder on first install.
if [[ -z "$APP_INSTALL" ]]; then
    if [[ -d "$SYSTEM_APP" || -d "$LEGACY_SYSTEM_APP" ]]; then
        APP_INSTALL="$SYSTEM_APP"
    else
        APP_INSTALL="$HOME_APP"
    fi
fi

"$ROOT/macos/scripts/build.sh"

EXT_DIR="${EXTENSION_DIR:-$ROOT}"
EXT_DIR="$(cd "$EXT_DIR" && pwd -P)"
EXT_ID="$(printf '%s' "$EXT_DIR" | shasum -a 256 | cut -c1-32 | tr '0-9a-f' 'a-p')"

if [[ ${#EXT_ID} -ne 32 ]]; then
    echo "error: could not compute the extension id" >&2
    exit 1
fi

mkdir -p "$SUPPORT_DIR/bin" "$MANIFEST_DIR" "$(dirname "$APP_INSTALL")"

# Upgrade from the previous branding: keep the old usage mirror, then remove
# the old app, host and native-messaging manifest.
if [[ -f "$LEGACY_SUPPORT_DIR/usage.json" && \
      ! -f "$SUPPORT_DIR/usage.json" ]]; then
    cp "$LEGACY_SUPPORT_DIR/usage.json" "$SUPPORT_DIR/usage.json"
    echo "Migrated usage data from: $LEGACY_SUPPORT_DIR"
fi
rm -f "$LEGACY_HOST_BIN" "$LEGACY_MANIFEST_PATH"
rm -rf "$LEGACY_SYSTEM_APP" "$LEGACY_HOME_APP"

rm -rf "$APP_INSTALL"
ditto "$ROOT/build/MacTimer.app" "$APP_INSTALL"

# If the user moved the app to /Applications, do not keep a stale duplicate
# in ~/Applications around to be launched by mistake.
if [[ "$APP_INSTALL" == "$SYSTEM_APP" && -d "$HOME_APP" ]]; then
    rm -rf "$HOME_APP"
    echo "Removed old copy: $HOME_APP"
fi

cp "$ROOT/build/MacTimerHost" "$HOST_BIN"
chmod 755 "$HOST_BIN"
codesign --force --sign - "$HOST_BIN" >/dev/null 2>&1 || true

cat > "$MANIFEST_PATH" <<EOF
{
  "name": "$HOST_NAME",
  "description": "MacTimer local data bridge",
  "path": "$HOST_BIN",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$EXT_ID/"]
}
EOF

echo
echo "已安装："
echo "  App:        $APP_INSTALL"
echo "  本地桥:     $HOST_BIN"
echo "  Chrome 清单: $MANIFEST_PATH"
echo
echo "扩展目录：$EXT_DIR"
echo "扩展 ID：  $EXT_ID"
echo
echo "接下来："
echo "  1. 打开 chrome://extensions，对「MacTimer」点一次 Reload（新增了本地通信权限）。"
echo "  2. 点击扩展图标，在弹窗底部点「同步到 Mac」。"
echo "  3. 打开 $APP_INSTALL 查看网页数据。"
echo "  4. 如要把 App 使用时间合并进来，在 App 顶部提示中点「打开系统设置」，"
echo "     或手动进入：系统设置 → 隐私与安全性 → 完全磁盘访问权限，"
echo "     添加 ${APP_INSTALL}。授权后如仍不可用，请退出并重新打开 App。"
echo
echo "如果扩展不是从上面的目录加载的，请用："
echo "  EXTENSION_DIR=/实际/扩展目录 $ROOT/macos/scripts/install.sh"
