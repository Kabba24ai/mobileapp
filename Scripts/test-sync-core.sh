#!/bin/bash
#
# Runs the Sync Engine core unit tests (RentnKingTests/KabbaSyncCore) on macOS.
#
#   1. If xcodebuild is usable (Xcode license accepted) → `swift test` via Package.swift.
#   2. Otherwise → compile core + tests straight into an .xctest bundle with the Xcode
#      toolchain's swiftc and run it with the `xctest` runner. Same tests, same
#      assertions; only the build driver differs.
#
# Exit code is the test result.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEV="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR="$DEV"

if "$DEV/usr/bin/xcrun" --sdk macosx --show-sdk-path >/dev/null 2>&1; then
    echo "▶ Xcode toolchain available — running: swift test"
    cd "$ROOT"
    exec "$DEV/usr/bin/swift" test
fi

echo "▶ xcodebuild unavailable (Xcode license not accepted?) — building the XCTest bundle directly"

TC="$DEV/Toolchains/XcodeDefault.xctoolchain/usr/bin"
PLAT="$DEV/Platforms/MacOSX.platform/Developer"
SDK="$PLAT/SDKs/MacOSX.sdk"
ARCH="$(uname -m)"
BUILD="$ROOT/.build/sync-core-tests"
BUNDLE="$BUILD/KabbaSyncCoreTests.xctest"

rm -rf "$BUILD"
mkdir -p "$BUNDLE/Contents/MacOS"

"$TC/swiftc" \
    -swift-version 5 \
    -sdk "$SDK" \
    -target "$ARCH-apple-macosx12.0" \
    -module-name KabbaSyncCoreTests \
    -emit-library \
    -o "$BUNDLE/Contents/MacOS/KabbaSyncCoreTests" \
    -F"$PLAT/Library/Frameworks" \
    -I"$PLAT/usr/lib" \
    -L"$PLAT/usr/lib" \
    -Xlinker -rpath -Xlinker "$PLAT/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "$PLAT/Library/PrivateFrameworks" \
    -Xlinker -rpath -Xlinker "$PLAT/usr/lib" \
    "$ROOT"/RentnKing/Sync/Core/*.swift \
    "$ROOT"/RentnKingTests/KabbaSyncCore/*.swift \
    2>&1 | grep -v '^ld: warning' || true

if [ ! -f "$BUNDLE/Contents/MacOS/KabbaSyncCoreTests" ]; then
    echo "✖ compile failed"
    exit 1
fi

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>ai.kabba.KabbaSyncCoreTests</string>
    <key>CFBundleExecutable</key><string>KabbaSyncCoreTests</string>
    <key>CFBundlePackageType</key><string>BNDL</string>
</dict>
</plist>
PLIST

export DYLD_FRAMEWORK_PATH="$PLAT/Library/Frameworks:$PLAT/Library/PrivateFrameworks"
export DYLD_LIBRARY_PATH="$PLAT/usr/lib"
exec "$DEV/usr/bin/xctest" "$BUNDLE"
