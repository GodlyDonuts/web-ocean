#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
extension_path="$PWD/macos/build/Ocean.app/Contents/PlugIns/OceanLiveWallpaper.appex"
rm -rf "$PWD/macos/build/Ocean.app/Contents/PlugIns/OceanWallpaper.appex"
mkdir -p "$extension_path/Contents/MacOS" "$extension_path/Contents/Resources"
xcrun clang -fobjc-arc -c macos/WallpaperExtension/WallpaperBridge.m -o macos/build/WallpaperBridge.o
xcrun swiftc -O -parse-as-library -module-name OceanLiveWallpaper \
 -import-objc-header macos/WallpaperExtension/WallpaperProtocols.h \
 -Xlinker -e -Xlinker _NSExtensionMain -Xlinker -application_extension \
 macos/WallpaperExtension/*.swift macos/build/WallpaperBridge.o \
 macos/SharedSurfaceDemand.swift macos/CelestialCycle.swift macos/ObserverLocationProvider.swift macos/Weather.swift macos/WeatherProvider.swift macos/OceanRenderer.swift macos/CloudNoise.swift macos/StarField.swift macos/GalaxyAtlas.swift macos/GPUProfiler.swift macos/ViewportLayout.swift macos/ViewportMesh.swift macos/MipmapRounding.swift macos/AnimationClock.swift macos/PerformancePolicy.swift macos/RegionalRendering.swift macos/ScreenSaverEnvironment.swift macos/LiveWallpaperControl.swift \
 -o "$extension_path/Contents/MacOS/OceanLiveWallpaper" \
 -framework AppKit -framework IOKit -framework ScreenSaver -framework Metal -framework MetalKit -framework QuartzCore -framework IOSurface -framework ExtensionFoundation \
 -target "$(uname -m)-apple-macosx26.0"
ditto macos/build/Ocean.app/Contents/Resources/Shaders "$extension_path/Contents/Resources/Shaders"
ditto macos/build/Ocean.app/Contents/Resources/Assets "$extension_path/Contents/Resources/Assets"
cp macos/WallpaperExtension/Info.plist "$extension_path/Contents/Info.plist"
cp macos/WallpaperExtension/OceanFallback.png macos/WallpaperExtension/Aerial-LICENSE "$extension_path/Contents/Resources/"
codesign --force --sign - --entitlements macos/WallpaperExtension/OceanWallpaper.entitlements "$extension_path"
echo "Built $extension_path"
