# FFT rotation-table experiment

This candidate is not used by the app. It computes 1,024 float32 stage/lane rotations once on the GPU and binds the 8 KiB table to row and column transforms.

On this Apple M1 it did not improve whole-frame GPU time, and it changed some rounded results. The production kernels retain their original trigonometric expressions. `accuracy.json` records numerical differences against the original kernels and independent double-precision DFT samples; `benchmark.json` records eight alternating app runs. These reports do not certify bit-exact output.

From the repository root, reproduce the standalone accuracy measurements with:

```sh
xcrun swiftc -O -parse-as-library macos/Tests/Experiments/FFTTable/Verification.swift -framework Metal -o macos/build/FFTTableVerification
macos/build/FFTTableVerification
```

The standalone comparison reports float32 row differences, float16 assembled differences (including signed zero), and DFT errors for zero, impulse, single-frequency and random inputs. It does not enable the candidate in the app.
