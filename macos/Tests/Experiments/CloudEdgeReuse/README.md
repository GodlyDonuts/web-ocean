# Rejected direct cloud-edge reuse

The visible sky evaluates low/high cloud edges for antialiasing and then inside `cloudLayers` for density. This candidate passed the precomputed edge pair into that function; sun-disk evaluations kept the original path.

The first six initial-clock states matched raw HDR, display and all cached sky/environment/sun data. The stable-clock case changed output, so the candidate failed the unchanged-output gate and was not benchmarked or adopted. `quality.json` records the checked states and differences. Identical source equations do not establish identical compiler output in every calling context.

Snapshots are excluded from the native build. To reproduce in a disposable project copy, put the shader under `macos/Shaders/`, controller under `macos/`, and drivers under `macos/Tests/`, build, and run `python3 macos/Tests/verify_clouds.py --reuse-edges`. `reuseCloudEdges=0` selects the reference path.
