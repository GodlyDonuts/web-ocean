# Rejected ocean cascade-loop unrolling

The refreshed profile after wave fusion reported about 3.71 ms for ocean-and-sky fragment work, 1.74 ms for waves, and 0.96 ms amortized visible-sky work. These stage counters are instrumented and nonadditive.

Full loop unrolling changed 112 HDR values and three final display bytes in the first scene. Disabling reassociation across the loop still changed 50 HDR values; preserving loop-carried sums with an ordered helper changed 37. These variants failed the quality gate and were not benchmarked or adopted.

Two-way partial unrolling matched all twelve image states and original wave/foam mip data exactly. Eight ordinary interleaved runs changed average GPU time by only 0.19% and median by 0.23%, so it did not justify adoption. CPU differences are not claimed as a gain. `results.json` records the profile, failures, quality checks and timings.

All variants are archived and excluded from the app. The `partialTwo/` snapshots include the controller and test drivers. In a disposable project copy, replace `macos/Shaders/OCEAN.metal`, `macos/OceanRenderer.swift`, `macos/Tests/benchmark.py` and `macos/Tests/compare_quality.py` with those snapshots, build, then run:

```sh
python3 macos/Tests/compare_quality.py --unroll-ocean
python3 macos/Tests/benchmark.py --baseline unroll --rounds 2
```

`unrollOcean=0` selects the accepted reference loop. To reproduce a rejected full variant, substitute its shader while keeping the same archived controller/driver. Production retains the original loop.
