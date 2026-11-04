#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
zsh macos/build.sh
python3 macos/Tests/verify_headless.py
xcrun swiftc -O -parse-as-library macos/ViewportLayout.swift macos/Tests/ViewportLayoutTests.swift -o macos/build/ViewportLayoutTests
macos/build/ViewportLayoutTests
xcrun swiftc -O -parse-as-library macos/ViewportMesh.swift macos/Tests/ViewportMeshTests.swift -o macos/build/ViewportMeshTests
macos/build/ViewportMeshTests
xcrun swiftc -O -parse-as-library macos/AnimationClock.swift macos/Tests/AnimationClockTests.swift -o macos/build/AnimationClockTests
macos/build/AnimationClockTests
xcrun swiftc -O -parse-as-library macos/Tests/EvolutionFFTVerification.swift -framework Metal -o macos/build/EvolutionFFTVerification
macos/build/EvolutionFFTVerification
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 macos/build/Ocean.app/Contents/MacOS/Ocean --verify --profile '--query=renderWidth=759&renderHeight=1349'
python3 macos/Tests/compare_quality.py
python3 macos/Tests/compare_quality.py --fused-evolution
python3 macos/Tests/compare_quality.py --shared-cubic
python3 macos/Tests/compare_quality.py --historical-geometry
python3 macos/Tests/verify_coverage.py
python3 macos/Tests/verify_time.py
python3 macos/Tests/verify_clouds.py
python3 macos/Tests/verify_clouds.py --inactive-aa --cleanup
python3 macos/Tests/verify_texture_usage.py
if [[ "${1:-}" == "--fft-experiment" ]]; then
  xcrun swiftc -O -parse-as-library macos/Tests/FFTVerification.swift -framework Metal -o macos/build/FFTVerification
  macos/build/FFTVerification
fi
