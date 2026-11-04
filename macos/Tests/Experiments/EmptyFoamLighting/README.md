# Rejected empty-foam lighting branch

The candidate uses a SIMD-uniform `simd_any(foamMask > 0)` condition to skip bubble-texture sampling and foam lighting where all active lanes have zero foam weight. The original implicit texture sample is retained, and debug mode six forces lighting evaluation for its unmasked output.

The first sunset comparison changed 28 HDR half-float values, so the candidate failed the unchanged-output gate and was not benchmarked or adopted. The planned calm and foam-debug cases were not reached. See `quality-failure.json`.

These snapshots are excluded from the app. To reproduce in a disposable project copy, put the shader under `macos/Shaders/`, controller under `macos/`, and Python drivers under `macos/Tests/`, build, then run `python3 macos/Tests/compare_quality.py --empty-foam-lighting`. `skipEmptyFoamLighting=0` selects the accepted path. No performance or quality improvement is claimed.
