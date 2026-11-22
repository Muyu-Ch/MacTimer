#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MACOS_DIR="$ROOT/macos"
DIST="$ROOT/dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$MACOS_DIR/Resources/Info.plist" 2>/dev/null || true)"

if [[ -z "$VERSION" ]]; then
    echo "error: could not read CFBundleShortVersionString" >&2
    exit 1
fi

if [[ "${1:-}" != "--skip-build" ]]; then
    "$MACOS_DIR/scripts/build.sh"
fi

if [[ ! -d "$ROOT/build/MacTimer.app" || ! -f "$ROOT/build/MacTimerHost" ]]; then
    echo "error: build/MacTimer.app or build/MacTimerHost is missing" >&2
    echo "       run without --skip-build, or run macos/scripts/build.sh first" >&2
    exit 1
fi

rm -rf "$DIST"
mkdir -p "$DIST"

EXTENSION_ZIP="$DIST/MacTimer-Chrome-Extension-$VERSION.zip"
(
    cd "$ROOT"
    zip -r -X "$EXTENSION_ZIP" \
        manifest.json background.js shared.js \
        popup.html popup.css popup.js icons
)

STAGE="$DIST/.dmg-stage"
mkdir -p "$STAGE"
ditto "$ROOT/build/MacTimer.app" "$STAGE/MacTimer.app"
ln -s /Applications "$STAGE/Applications"
cp "$MACOS_DIR/scripts/Install Native Host.command" \
    "$STAGE/Install Native Host.command"
chmod 755 "$STAGE/Install Native Host.command"
cp "$ROOT/build/MacTimerHost" "$STAGE/MacTimerHost"
chmod 755 "$STAGE/MacTimerHost"

cat > "$STAGE/README.txt" <<EOF
MacTimer $VERSION
=================

这是一个未经过 Apple 公证的版本。首次打开 App 时 macOS 可能提示
「无法验证开发者」或「已损坏」：

  - 优先：在 Finder 中右键 MacTimer.app → 打开 → 打开；
  - 或在 系统设置 → 隐私与安全性 → 仍要打开；
  - 不要关闭整个系统的 Gatekeeper。

安装步骤
--------

1. 从同一个 GitHub Release 下载对应的 Chrome 扩展 ZIP，并解压。
2. 把 MacTimer.app 拖到 Applications 文件夹。
3. 双击 Install Native Host.command。如果被系统拦截，
   右键 → 打开。选择第 1 步解压出的扩展目录（里面要有
   manifest.json）。
4. 在 Chrome 打开 chrome://extensions，启用「开发者模式」，
   点击「加载已解压的扩展程序」，选择：

     ~/Library/Application Support/MacTimer/Extension

   这是本地桥安装脚本复制出的稳定目录，不要改成 Downloads
   里的原解压目录，否则扩展 ID 会和本地桥清单不匹配。
5. 打开 MacTimer.app。为了让 App 读取 Screen Time 和应用数据，
   在 系统设置 → 隐私与安全性 → 完全磁盘访问权限 中添加
   /Applications/MacTimer.app。
6. 点击扩展图标 → 同步到 Mac。如果 App 仍提示未授权，
   退出 App 后重新打开。

注意：App 更新后代码签名可能变化，完全磁盘访问权限可能需要
移除并重新添加。扩展的稳定目录可以保留，不要随意移动。
EOF

DMG="$DIST/MacTimer-$VERSION.dmg"
hdiutil create \
    -volname "MacTimer $VERSION" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null
rm -rf "$STAGE"

(
    cd "$DIST"
    shasum -a 256 \
        "MacTimer-$VERSION.dmg" \
        "MacTimer-Chrome-Extension-$VERSION.zip" \
        > SHA256SUMS.txt
)

echo
echo "Release assets:"
ls -lh "$DIST"
