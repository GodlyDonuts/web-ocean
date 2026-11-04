# Rejected reflection-cube mip fusion

The candidate preserves the original 4-by-4 [1,3,3,1] weighted filter and clamps at each face edge. It leaves the first 128-to-64 reduction unchanged and computes all six remaining levels in one 256-thread group per face. Disjoint half4 scratch ranges and the existing startup rounding probe preserve intermediate half precision. Reflection mip dispatches fall from seven to two.

All nine captured scenes matched raw HDR, final display bytes, cached sky, every reflection face and mip, and sun visibility exactly. Comparisons used a nonzero fixed timestep, exercising initial six-face generation and later incremental face updates.

Twenty-eight ordinary interleaved runs did not establish a repeatable benefit. Initial CPU wall-time improvements did not hold in the twelve-run repeat with thread CPU measurements. Average GPU time was effectively unchanged. Do not ship this candidate based on its dispatch count alone.

`results.json` contains all runs, stage profiles and quality data. Stage profiles perturb scheduling and are not additive production timings. Results apply only to the tested Apple M1 and scene settings.

These are archived candidate snapshots, excluded from the app build. To reproduce in a disposable copy, replace `macos/OceanRenderer.swift`, `macos/Shaders/manifest.json`, `macos/Tests/benchmark.py`, and `macos/Tests/verify_clouds.py` with these snapshots; copy `CUBE_MIPS_FUSED_TAIL.metal` into `macos/Shaders/`. Then build and run:

```sh
zsh macos/build.sh
python3 macos/Tests/verify_clouds.py --cube-mips
python3 macos/Tests/benchmark.py --baseline cube --rounds 3
```

`fusedCubeMips=0` selects the original seven-dispatch chain. Normal production keeps that original chain; only the benchmark-only thread CPU timer is retained.
