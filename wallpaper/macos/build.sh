#!/bin/bash
set -euo pipefail

# Build a native menu-bar application without Xcode project dependencies.
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
APP="$ROOT/dist/OceanWallpaper.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

if [[ "$(uname -s)" != Darwin ]]; then
  echo "Build on macOS 26+ with Xcode Command Line Tools." >&2
  exit 1
fi
if [[ ! -f "$ROOT/ocean.min.html" ]]; then
  echo "Missing ocean.min.html. Run 'npm run build' at the repo root." >&2
  exit 1
fi

mkdir -p "$MACOS" "$RES"
ARCH="$(uname -m)"
xcrun swiftc \
  -O -whole-module-optimization -parse-as-library \
  -target "$ARCH-apple-macosx26.0" \
  -framework AppKit -framework WebKit -framework CoreGraphics \
  "$HERE/OceanWallpaper.swift" \
  -o "$MACOS/OceanWallpaper"

cp "$ROOT/ocean.min.html" "$RES/ocean.html"
cp "$HERE/FrameGovernor.js" "$RES/FrameGovernor.js"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>io.github.godlydonuts.ocean-wallpaper</string>
  <key>CFBundleExecutable</key>
  <string>OceanWallpaper</string>
  <key>CFBundleName</key>
  <string>Ocean Wallpaper</string>
  <key>CFBundleDisplayName</key>
  <string>Ocean Wallpaper</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>0.1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# For local builds only. Distribution needs a proper Developer ID signature.
codesign --force --sign - "$APP"
echo "Built: $APP"
echo "Run with: open \"$APP\""
