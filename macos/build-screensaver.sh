#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
saver_path="$PWD/macos/build/Ocean.saver"
mkdir -p "$saver_path/Contents/MacOS" "$saver_path/Contents/Resources"
xcrun swiftc -O -emit-library -Xlinker -bundle -module-name OceanScreenSaver macos/ScreenSaver/OceanScreenSaver.swift \
 macos/SharedSurfaceDemand.swift macos/CelestialCycle.swift macos/ObserverLocationProvider.swift macos/Weather.swift macos/WeatherProvider.swift macos/OceanRenderer.swift macos/CloudNoise.swift macos/StarField.swift macos/GalaxyAtlas.swift macos/GPUProfiler.swift macos/ViewportLayout.swift macos/ViewportMesh.swift macos/MipmapRounding.swift macos/AnimationClock.swift macos/PerformancePolicy.swift macos/RegionalRendering.swift macos/ScreenSaverEnvironment.swift \
 -o "$saver_path/Contents/MacOS/OceanScreenSaver" \
 -framework AppKit -framework IOKit -framework ScreenSaver -framework Metal -framework MetalKit -framework QuartzCore \
 -target "$(uname -m)-apple-macosx13.0"
ditto macos/build/Ocean.app/Contents/Resources/Shaders "$saver_path/Contents/Resources/Shaders"
ditto macos/build/Ocean.app/Contents/Resources/Assets "$saver_path/Contents/Resources/Assets"
cp macos/ScreenSaver/Info.plist "$saver_path/Contents/Info.plist"
codesign --force --sign - "$saver_path"
echo "Built $saver_path"
