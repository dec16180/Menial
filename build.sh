#!/usr/bin/env bash
# Builds Menial.app from source.
#   ./build.sh            → build/Menial.app
#   ./build.sh --install  → also copies it to /Applications and launches it
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift isn't installed. Install the Xcode Command Line Tools first:" >&2
  echo "    xcode-select --install" >&2
  exit 1
fi

echo "→ Compiling Menial (release)…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Menial.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Menial" "$APP/Contents/MacOS/Menial"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "✓ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Menial 2>/dev/null || true
  rm -rf /Applications/Menial.app
  # The app used to be called TodoBar; remove that copy so only one runs.
  if [[ -d /Applications/TodoBar.app ]]; then
    pkill -x TodoBar 2>/dev/null || true
    rm -rf /Applications/TodoBar.app
    echo "→ Removed the old /Applications/TodoBar.app"
  fi
  cp -R "$APP" /Applications/
  open /Applications/Menial.app
  echo "✓ Installed to /Applications and launched. Look for the checklist icon in your menu bar."
else
  echo "Launch it with:  open $APP"
  echo "Or install it:   ./build.sh --install"
fi
