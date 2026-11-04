#!/bin/zsh
# Maintained handoff gate. GPU captures are windowless and deterministic.
set -eu
cd "$(dirname "$0")/.."
zsh macos/build.sh
zsh macos/test-unit.sh
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 python3 macos/Tests/verify_day_night.py
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 python3 macos/Tests/verify_weather.py
python3 macos/Tests/verify_night_water.py
python3 macos/Tests/verify_coverage.py
python3 macos/Tests/verify_headless.py
