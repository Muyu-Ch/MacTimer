#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MACOS_DIR="$ROOT/macos"

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

if [[ -n "$PLUGIN_DIR" ]]; then
    "$SWIFT" test --package-path "$MACOS_DIR" \
        -Xswiftc -plugin-path -Xswiftc "$PLUGIN_DIR"
else
    "$SWIFT" test --package-path "$MACOS_DIR"
fi
