#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
zsh macos/build.sh
xcrun swiftc -O -parse-as-library macos/CelestialCycle.swift macos/Tests/CelestialCycleTests.swift -o macos/build/CelestialCycleTests
macos/build/CelestialCycleTests
xcrun swiftc -O -parse-as-library macos/CelestialCycle.swift macos/ObserverLocationProvider.swift macos/Tests/IPLocationTests.swift -o macos/build/IPLocationTests
macos/build/IPLocationTests
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 python3 macos/Tests/verify_day_night.py
mkdir -p macos/build/celestial-motion
xcrun swiftc -O -parse-as-library macos/CelestialCycle.swift macos/Tests/CelestialMotionTests.swift -o macos/build/celestial-motion/CelestialMotionTests
macos/build/celestial-motion/CelestialMotionTests
python3 macos/Tests/verify_celestial_motion.py
mkdir -p macos/build/unit
xcrun swiftc -O -parse-as-library macos/CelestialCycle.swift macos/Tests/WallpaperMoonTests.swift -o macos/build/unit/WallpaperMoonTests
macos/build/unit/WallpaperMoonTests
python3 macos/Tests/verify_wallpaper_moon.py
zsh macos/Tests/test-night-resources.sh
