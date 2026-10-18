#!/usr/bin/env bash
# Builds TodoBar.app from source.
#   ./build.sh            → build/TodoBar.app
#   ./build.sh --install  → also copies it to /Applications and launches it
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift isn't installed. Install the Xcode Command Line Tools first:" >&2
  echo "    xcode-select --install" >&2
  exit 1
fi

echo "→ Compiling TodoBar (release)…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/TodoBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TodoBar" "$APP/Contents/MacOS/TodoBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "✓ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x TodoBar 2>/dev/null || true
  rm -rf /Applications/TodoBar.app
  cp -R "$APP" /Applications/
  open /Applications/TodoBar.app
  echo "✓ Installed to /Applications and launched. Look for the checklist icon in your menu bar."
else
  echo "Launch it with:  open $APP"
  echo "Or install it:   ./build.sh --install"
fi
