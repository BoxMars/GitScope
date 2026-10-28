#!/bin/bash
# Build GitScope into build/GitScope.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SDK="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk"
SWIFTC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"

MODE="${1:-debug}"
APP="$ROOT/build/GitScope.app"
CACHE="$ROOT/.cache"
mkdir -p "$CACHE/modules" "$CACHE/tmp" "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(find "$ROOT/Sources" -name '*.swift' | sort)

FLAGS=(-sdk "$SDK" -target arm64-apple-macos14.0 -module-name GitScope -parse-as-library -disable-sandbox
       -module-cache-path "$CACHE/modules" -swift-version 5
       -Xfrontend -disable-availability-checking)
if [ "$MODE" = "release" ]; then
  FLAGS+=(-O)
else
  FLAGS+=(-Onone -g)
fi

TMPDIR="$CACHE/tmp" "$SWIFTC" "${FLAGS[@]}" -o "$APP/Contents/MacOS/GitScope" "${SOURCES[@]}"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"
echo "built $APP ($MODE)"
