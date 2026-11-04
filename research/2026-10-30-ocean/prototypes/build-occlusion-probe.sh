#!/bin/bash
set -euo pipefail

PROBE_ROOT="$(cd "$(dirname "$0")" && pwd)"
PROBE_APP="$PROBE_ROOT/build/OcclusionProbe.app"
PROBE_BIN="$PROBE_APP/Contents/MacOS"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Build this diagnostic on macOS 26+ with Xcode Command Line Tools." >&2
  exit 1
fi

mkdir -p "$PROBE_BIN"
xcrun swiftc -O -whole-module-optimization -parse-as-library \
  -target "$(uname -m)-apple-macosx26.0" \
  -framework AppKit -framework CoreGraphics \
  "$PROBE_ROOT/OcclusionProbe.swift" -o "$PROBE_BIN/OcclusionProbe"

cat > "$PROBE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.godlydonuts.ocean-occlusion-probe</string>
  <key>CFBundleExecutable</key><string>OcclusionProbe</string>
  <key>CFBundleName</key><string>Ocean Occlusion Probe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --sign - "$PROBE_APP"
echo "Built: $PROBE_APP"
echo "Run from Terminal to see JSON Lines (keep the quotes):"
echo "  \"$PROBE_BIN/OcclusionProbe\" --tiled"
echo "Use the ◫ menu to compare 1 × 1 and 4 × 3, take a snapshot, or quit."
