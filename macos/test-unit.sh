#!/bin/zsh
# CPU-only contracts; safe for hosted macOS CI without a GPU/display.
set -eu
cd "$(dirname "$0")/.."
mkdir -p macos/build/unit macos/build/celestial-motion
run_unit() {
  local test_name="$1"
  shift
  xcrun swiftc -O -parse-as-library "$@" "macos/Tests/${test_name}.swift" -o "macos/build/unit/${test_name}"
  "macos/build/unit/${test_name}"
}
run_unit WeatherTests macos/Weather.swift
run_unit WeatherProviderTests macos/CelestialCycle.swift macos/Weather.swift macos/WeatherProvider.swift
run_unit CelestialCycleTests macos/CelestialCycle.swift
run_unit IPLocationTests macos/CelestialCycle.swift macos/ObserverLocationProvider.swift
run_unit CelestialMotionTests macos/CelestialCycle.swift
run_unit ViewportLayoutTests macos/ViewportLayout.swift
run_unit ViewportMeshTests macos/ViewportMesh.swift
run_unit DisplayDemandTests macos/Diagnostics/DisplayTileLayout.swift macos/SharedSurfaceDemand.swift
run_unit AnimationClockTests macos/AnimationClock.swift
run_unit PerformancePolicyTests macos/PerformancePolicy.swift
run_unit NightEffectsTests macos/NightEffects.swift
