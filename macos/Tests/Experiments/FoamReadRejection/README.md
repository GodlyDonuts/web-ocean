# Rejected zero-weight foam sample pruning

The first variant computed explicit UV derivatives before conditional sampling. It changed 576 HDR values and 53 final display bytes in the first scene, so it failed the quality gate and was not benchmarked.

The second retained the original implicit sample calls behind SIMD-uniform conditions. It skipped clipmap samples only when no active lane needed their blend weight. Twelve scenes matched HDR, display bytes and wave/foam mip data exactly. Eight interleaved ordinary runs showed effectively unchanged GPU time, so this variant also remains archived. CPU timing differences are not claimed as a benefit.

`results.json` contains both outcomes and all timing runs. Snapshots are excluded from the app. To reproduce in a disposable project copy, put `OCEAN.metal` under `macos/Shaders/`, the controller under `macos/`, and drivers under `macos/Tests/`, then build and run:

```sh
python3 macos/Tests/compare_quality.py --skip-foam-reads
python3 macos/Tests/benchmark.py --baseline foamreads --rounds 2
```

`skipFoamReads=0` selects the accepted path. Substitute `OCEAN_EXPLICIT_GRADIENTS.metal` as `OCEAN.metal` to reproduce the first rejected variant. Tests were performed on one Apple M1.
