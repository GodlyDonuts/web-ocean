#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
zsh macos/build.sh
mkdir -p macos/build/weather
xcrun swiftc -O -parse-as-library macos/Weather.swift macos/Tests/WeatherTests.swift -o macos/build/weather/WeatherTests
macos/build/weather/WeatherTests
xcrun swiftc -O -parse-as-library macos/CelestialCycle.swift macos/Weather.swift macos/WeatherProvider.swift macos/Tests/WeatherProviderTests.swift -o macos/build/weather/WeatherProviderTests
macos/build/weather/WeatherProviderTests
python3 macos/Tests/verify_weather.py
python3 macos/Tests/verify_night_water.py
python3 macos/Tests/verify_headless.py
python3 macos/Tests/verify_volumetric_clouds.py
python3 macos/Tests/verify_cloud_motion.py
xcrun swiftc -O -parse-as-library macos/CelestialCycle.swift macos/Tests/CelestialCycleTests.swift -o macos/build/CelestialCycleTests
macos/build/CelestialCycleTests
xcrun swiftc -O -parse-as-library macos/CelestialCycle.swift macos/ObserverLocationProvider.swift macos/Tests/IPLocationTests.swift -o macos/build/IPLocationTests
macos/build/IPLocationTests
python3 macos/Tests/verify_day_night.py
mkdir -p macos/build/celestial-motion
xcrun swiftc -O -parse-as-library macos/CelestialCycle.swift macos/Tests/CelestialMotionTests.swift -o macos/build/celestial-motion/CelestialMotionTests
macos/build/celestial-motion/CelestialMotionTests
python3 macos/Tests/verify_celestial_motion.py
zsh macos/Tests/test-night-resources.sh
xcrun swiftc -O -parse-as-library macos/ViewportLayout.swift macos/Tests/ViewportLayoutTests.swift -o macos/build/ViewportLayoutTests
macos/build/ViewportLayoutTests
xcrun swiftc -O -parse-as-library macos/ViewportMesh.swift macos/Tests/ViewportMeshTests.swift -o macos/build/ViewportMeshTests
xcrun swiftc -O -parse-as-library macos/Diagnostics/DisplayTileLayout.swift macos/SharedSurfaceDemand.swift macos/Tests/DisplayDemandTests.swift -o macos/build/DisplayDemandTests
macos/build/DisplayDemandTests
macos/build/ViewportMeshTests
xcrun swiftc -O -parse-as-library macos/AnimationClock.swift macos/Tests/AnimationClockTests.swift -o macos/build/AnimationClockTests
macos/build/AnimationClockTests
xcrun swiftc -O -parse-as-library macos/Tests/EvolutionFFTVerification.swift -framework Metal -o macos/build/EvolutionFFTVerification
macos/build/EvolutionFFTVerification
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 macos/build/Ocean.app/Contents/MacOS/Ocean --verify --profile '--query=renderWidth=759&renderHeight=1349'
python3 macos/Tests/compare_quality.py --fused-evolution
python3 macos/Tests/compare_quality.py --shared-cubic
python3 macos/Tests/verify_coverage.py
python3 macos/Tests/verify_time.py
python3 macos/Tests/verify_clouds.py
python3 macos/Tests/verify_clouds.py --inactive-aa --cleanup
python3 macos/Tests/verify_texture_usage.py
if [[ "${1:-}" == "--fft-experiment" ]]; then
  xcrun swiftc -O -parse-as-library macos/Tests/FFTVerification.swift -framework Metal -o macos/build/FFTVerification
  macos/build/FFTVerification
fi
