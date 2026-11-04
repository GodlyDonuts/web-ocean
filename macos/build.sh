#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
app_path="$PWD/macos/build/Ocean.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources/Shaders"
xcrun swiftc -O macos/main.swift macos/SharedSurfaceDemand.swift macos/CelestialCycle.swift macos/ObserverLocationProvider.swift macos/Weather.swift macos/WeatherProvider.swift macos/OceanRenderer.swift macos/CloudNoise.swift macos/StarField.swift macos/GalaxyAtlas.swift macos/GPUProfiler.swift macos/ViewportLayout.swift macos/ViewportMesh.swift macos/MipmapRounding.swift macos/AnimationClock.swift macos/PerformancePolicy.swift \
  -o "$app_path/Contents/MacOS/Ocean" \
  -framework AppKit -framework Metal -framework MetalKit -framework QuartzCore -framework IOKit -framework ServiceManagement \
  -target "$(uname -m)-apple-macosx13.0"
cp macos/Shaders/*.metal macos/Shaders/*.metalinc macos/Shaders/manifest.json "$app_path/Contents/Resources/Shaders/"
# Remove the previous browser payload from existing app bundles.
rm -f "$app_path/Contents/Resources/ocean.html"
mkdir -p "$app_path/Contents/Resources/Assets/Galaxy"
cp macos/Assets/Galaxy/* "$app_path/Contents/Resources/Assets/Galaxy/"
cp macos/Info.plist "$app_path/Contents/Info.plist"
codesign --force --sign - "$app_path"
echo "Built $app_path (native Metal)"
