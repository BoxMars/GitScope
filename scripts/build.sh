#!/bin/bash
# Build GitScope.app  (usage: ./scripts/build.sh [debug|release])
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-debug}"

# Prefer a full Xcode toolchain; fall back to the active developer dir.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || echo /Library/Developer/CommandLineTools)}"

SWIFTC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
if [ ! -x "$SWIFTC" ]; then
  SWIFTC="$(xcrun -f swiftc)"
fi

SDK="$(ls -d "$DEVELOPER_DIR"/Platforms/MacOSX.platform/Developer/SDKs/MacOSX*.sdk 2>/dev/null | sort -V | tail -1 || true)"
if [ -z "${SDK:-}" ] || [ ! -d "$SDK" ]; then
  SDK="$(xcrun --sdk macosx --show-sdk-path)"
fi

ARCH="$(uname -m)"
[ "$ARCH" = "arm64" ] || ARCH="x86_64"

APP="$ROOT/build/GitScope.app"
CACHE="$ROOT/.cache"
mkdir -p "$CACHE/modules" "$CACHE/tmp" "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=()
while IFS= read -r f; do SOURCES+=("$f"); done < <(find "$ROOT/Sources" -name '*.swift' | sort)

# -disable-sandbox: the Swift macro plugin server cannot nest sandbox-exec in
# restricted build environments. It only affects the compiler's own subprocesses.
FLAGS=(-sdk "$SDK" -target "$ARCH-apple-macos14.0" -module-name GitScope -parse-as-library
       -module-cache-path "$CACHE/modules" -swift-version 5 -disable-sandbox
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
echo "built $APP ($MODE, $ARCH, $(basename "$SDK"))"
