#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p macos/build/weather
zsh macos/build.sh
xcrun swiftc -O -parse-as-library macos/Weather.swift macos/Tests/WeatherTests.swift -o macos/build/weather/WeatherTests
macos/build/weather/WeatherTests
xcrun swiftc -O -parse-as-library macos/CelestialCycle.swift macos/Weather.swift macos/WeatherProvider.swift macos/Tests/WeatherProviderTests.swift -o macos/build/weather/WeatherProviderTests
macos/build/weather/WeatherProviderTests
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 python3 macos/Tests/verify_weather.py
