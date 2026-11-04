# Rejected concurrent compute scheduler

The candidate uses a serial first frame, then a concurrent compute encoder with explicit stage barriers. Wave evolution overlaps the sky LUT; FFT rows overlap sun visibility and the environment cube; FFT columns and wave/foam mip stages overlap successive cube mips. Narrow-view bounds share independent wave-mip stages. Foam waits for every wave mip because it samples nonzero LODs. Shared lighting runs after both sun visibility and all environment mips are complete. Profiling retains the serial path.

The eight interleaved runs changed average GPU time by about 0.2% and median by about 0.15%, with effectively unchanged average encoding-thread CPU time. This did not justify the additional scheduler. Twelve deterministic captures matched HDR, final display bytes, wave/foam mips and packed Jacobians exactly; these eight-frame captures do not cover a later sky/sun refresh. This candidate is archived, excluded from the app, and not claimed fully validated.

`results.json` records the measurements, checked states and limitations. To reproduce in a disposable project copy, replace the renderer, benchmark driver and quality driver with these snapshots, then run:

```sh
zsh macos/build.sh
python3 macos/Tests/compare_quality.py --concurrent
python3 macos/Tests/benchmark.py --baseline concurrent --rounds 2
```

`concurrentCompute=0` selects the original serial path. Native shaders are unchanged. Apple's resource synchronization guidance and the SDK's `MTLComputeCommandEncoder.h` specify that default compute dispatches are serial and `memoryBarrier` calls on a serial encoder are ignored. Production uses serial dispatches and removes those ignored calls.
