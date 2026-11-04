# FFT temporary-buffer layout experiments

Production retains the accepted fused evolution/row FFT and its row-major temporary buffers. All native source and test-driver hashes match the accepted evolution pass after this experiment.

Six compute-only variants use identical float32 evolution, butterfly arithmetic, and half-float texture assembly. They differ only in physical buffer addresses: row-major, column-major, and square 4/8/16/32 tiles. The CPU comparison reverses each mapping and checks every row bit; raw assembled displacement/derivative/moment texture bytes must also match. Addressing source is retained beside `Verification.swift`, independently of the native app. From the repository root:

```sh
xcrun swiftc -O -parse-as-library macos/Tests/Experiments/FFTLayout/Verification.swift -framework Metal -o macos/build/FFTLayoutVerification
macos/build/FFTLayoutVerification
```

`microbenchmark.json` records the initial six-round alternating sweep. Every measured command contains twelve fused-row/column pairs; timings exclude the quality readback. `microbenchmark-reproduction.json` records the self-contained reproduction after restoring production sources. These compute-only timings do not establish a full-frame gain.

Eight ordinary interleaved runs for each of column-major and tile16 failed to establish a useful whole-renderer GPU improvement. All twelve deterministic scene comparisons matched HDR, display bytes and wave/foam mip data for each candidate. CPU timing differences varied and are not claimed as an optimization. See `full-frame-results.json`.

`NaiveRenderer/` and `TiledRenderer/` hold the exact candidate shader/controller/driver snapshots. They are excluded from the app build. To repeat full-frame experiments, copy the corresponding shaders to `macos/Shaders/`, controller to `macos/`, and drivers to `macos/Tests/` in a disposable project copy, then build. Commands for the naive snapshot:

```sh
python3 macos/Tests/compare_quality.py --transposed-fft
python3 macos/Tests/benchmark.py --baseline transpose --rounds 2
```

For the tile16 snapshot:

```sh
python3 macos/Tests/compare_quality.py --tiled-fft
python3 macos/Tests/benchmark.py --baseline layout --rounds 2
```

The naive query switch is `transposedFFT=0|1`; the tiled switch is `tiledFFT=0|1`. Both require fused evolution. A candidate is only worth adopting after a useful whole-renderer improvement is measured with unchanged image quality. These snapshots were tested on one Apple M1.
