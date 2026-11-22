#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ICONS_DIR="$ROOT/icons"
OUT="$ROOT/macos/Resources/AppIcon.icns"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 "$ROOT/tools/make_icons.py"

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
cp "$ICONS_DIR/icon16.png" "$ICONSET/icon_16x16.png"
cp "$ICONS_DIR/icon32.png" "$ICONSET/icon_16x16@2x.png"
cp "$ICONS_DIR/icon32.png" "$ICONSET/icon_32x32.png"
cp "$ICONS_DIR/icon64.png" "$ICONSET/icon_32x32@2x.png"
cp "$ICONS_DIR/icon128.png" "$ICONSET/icon_128x128.png"
cp "$ICONS_DIR/icon256.png" "$ICONSET/icon_128x128@2x.png"
cp "$ICONS_DIR/icon256.png" "$ICONSET/icon_256x256.png"
cp "$ICONS_DIR/icon512.png" "$ICONSET/icon_256x256@2x.png"
cp "$ICONS_DIR/icon512.png" "$ICONSET/icon_512x512.png"
sips -z 1024 1024 "$ICONS_DIR/icon512.png" \
    --out "$ICONSET/icon_512x512@2x.png" >/dev/null

mkdir -p "$ROOT/macos/Resources"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "wrote $OUT"
