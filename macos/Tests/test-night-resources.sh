#!/bin/zsh
set -eu
cd "$(dirname "$0")/../.."
resource_app="$PWD/macos/build/NightSkyResourceTests.app"
mkdir -p "$resource_app/Contents/MacOS" "$resource_app/Contents/Resources/Assets/Galaxy"
cp macos/Assets/Galaxy/milkyway.r11g11b10f "$resource_app/Contents/Resources/Assets/Galaxy/"
cat > "$resource_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>ResourceTests</string><key>CFBundleIdentifier</key><string>local.wallpaper.resource-tests</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>
PLIST
xcrun swiftc -O -parse-as-library macos/GalaxyAtlas.swift macos/StarField.swift macos/Tests/NightSkyResourcesTests.swift -framework Metal -o "$resource_app/Contents/MacOS/ResourceTests"
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 "$resource_app/Contents/MacOS/ResourceTests"
