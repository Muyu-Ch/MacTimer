#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MACOS_DIR="$ROOT/macos"
BUILD_DIR="$ROOT/build"
APP_PATH="$BUILD_DIR/MacTimer.app"
CONFIG="release"

# The Command Line Tools toolchain on this macOS does not ship
# libSwiftUIMacros.dylib, so use an Xcode toolchain when one is available.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    for candidate in \
        "/Applications/Xcode.app/Contents/Developer" \
        "/Applications/Xcode-beta.app/Contents/Developer"; do
        if [[ -d "$candidate" ]]; then
            export DEVELOPER_DIR="$candidate"
            break
        fi
    done
fi

SWIFT="/usr/bin/swift"
if [[ -n "${DEVELOPER_DIR:-}" && -x \
    "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" ]]; then
    SWIFT="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
fi

PLUGIN_DIR=""
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    for candidate in \
        "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins" \
        "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins"; do
        if [[ -f "$candidate/libSwiftUIMacros.dylib" ]]; then
            PLUGIN_DIR="$candidate"
            break
        fi
    done
fi

if [[ -z "$PLUGIN_DIR" ]]; then
    echo "warning: libSwiftUIMacros.dylib was not found." >&2
    echo "         Install Xcode or Xcode-beta if the build fails." >&2
fi

swift_build() {
    if [[ -n "$PLUGIN_DIR" ]]; then
        "$SWIFT" build --package-path "$MACOS_DIR" -c "$CONFIG" \
            -Xswiftc -plugin-path -Xswiftc "$PLUGIN_DIR" "$@"
    else
        "$SWIFT" build --package-path "$MACOS_DIR" -c "$CONFIG" "$@"
    fi
}

echo "Building MacTimer (release)..."
swift_build --product MacTimer
swift_build --product MacTimerHost

if [[ -n "$PLUGIN_DIR" ]]; then
    BIN_DIR="$("$SWIFT" build --package-path "$MACOS_DIR" -c "$CONFIG" \
        --show-bin-path -Xswiftc -plugin-path -Xswiftc "$PLUGIN_DIR")"
else
    BIN_DIR="$("$SWIFT" build --package-path "$MACOS_DIR" -c "$CONFIG" \
        --show-bin-path)"
fi

if [[ ! -f "$BIN_DIR/MacTimer" || ! -f "$BIN_DIR/MacTimerHost" ]]; then
    echo "error: build products not found in $BIN_DIR" >&2
    exit 1
fi

if [[ ! -f "$MACOS_DIR/Resources/AppIcon.icns" ]]; then
    "$MACOS_DIR/scripts/make-app-icon.sh"
fi

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/MacTimer" "$APP_PATH/Contents/MacOS/MacTimer"
cp "$MACOS_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$MACOS_DIR/Resources/AppIcon.icns" \
    "$APP_PATH/Contents/Resources/AppIcon.icns"
if [[ -d "$MACOS_DIR/Resources/Support" ]]; then
    ditto "$MACOS_DIR/Resources/Support" \
        "$APP_PATH/Contents/Resources/Support"
fi
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"
chmod +x "$APP_PATH/Contents/MacOS/MacTimer"

codesign --force --deep --sign - "$APP_PATH" >/dev/null

mkdir -p "$BUILD_DIR"
cp "$BIN_DIR/MacTimerHost" "$BUILD_DIR/MacTimerHost"
chmod +x "$BUILD_DIR/MacTimerHost"
codesign --force --sign - "$BUILD_DIR/MacTimerHost" >/dev/null 2>&1 || true

echo "Built:"
echo "  $APP_PATH"
echo "  $BUILD_DIR/MacTimerHost"
