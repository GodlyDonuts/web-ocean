#!/bin/zsh
set -eu
cd "$(dirname "$0")/../.."
probe_app="$PWD/macos/build/OcclusionProbe.app"
mkdir -p "$probe_app/Contents/MacOS"
xcrun swiftc -O -whole-module-optimization -parse-as-library \
  macos/Diagnostics/DisplayTileLayout.swift macos/SharedSurfaceDemand.swift macos/Diagnostics/OcclusionProbe.swift \
  -framework AppKit -framework CoreGraphics -target "$(uname -m)-apple-macosx13.0" \
  -o "$probe_app/Contents/MacOS/OcclusionProbe"
cat > "$probe_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.godlydonuts.ocean-occlusion-probe</string>
<key>CFBundleExecutable</key><string>OcclusionProbe</string>
<key>CFBundleName</key><string>Ocean Occlusion Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$probe_app"
echo "Built $probe_app. Default/help and --describe-layout create no windows. --present explicitly enables desktop tiles."
