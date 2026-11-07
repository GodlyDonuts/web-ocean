#!/bin/zsh
# Maintained handoff gate. GPU captures are windowless and deterministic.
set -eu
cd "$(dirname "$0")/.."
zsh macos/build.sh
zsh macos/test-unit.sh
python3 macos/Tests/verify_wallpaper_lifecycle.py
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 python3 macos/Tests/verify_day_night.py
python3 macos/Tests/verify_wallpaper_moon.py
python3 macos/Tests/verify_daylight_time.py
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 python3 macos/Tests/verify_weather.py
python3 macos/Tests/verify_night_water.py
python3 macos/Tests/verify_coverage.py
python3 macos/Tests/verify_headless.py
