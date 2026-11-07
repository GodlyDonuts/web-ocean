# Resource measurements, 6 November 2026

Measured on an Apple M1 Mac with 8 GiB unified memory, macOS 26.7. Active rendering uses approximately 5–6% of one CPU core, a 97–121 MiB physical footprint, and 8–11 ms mean GPU work per frame at 1280×800 and 30 FPS. The retained optimization reduces covered-desktop polling and CPU wakeups. It makes no change to rendered quality or active GPU work.

The baseline is PR revision `eeafd019da839b38c557e34b01f9cc2e3fe94740`, built separately with the same read-only Metal allocation telemetry. The updated version adds the polling change below. [Machine-readable results](resource-usage-2026-11-06.json) retain settings, aggregate measurements and verification evidence; full disposable samples remain in `macos/build/resource-optimization/` on the measurement machine.

## Active rendering

| Scene | CPU before / after (% of one core) | Physical footprint before / after (MiB, median) | GPU mean before / after (ms) | GPU P95 before / after (ms) |
|---|---:|---:|---:|---:|
| Daylight | 4.78 / 5.38 | 97.38 / 97.61 | 8.34 / 7.81 | 14.32 / 13.54 |
| Moonless night | 5.23 / 5.71 | 97.64 / 97.61 | 8.25 / 7.71 | 13.04 / 12.44 |
| Night storm | 5.21 / 5.16 | 119.75 / 121.31 | 11.06 / 10.03 | 23.91 / 22.61 |

These are short sequential runs, one before/after pair per scene. Active timings vary between runs; there is **no adopted active GPU optimization and no claimed GPU speedup**. GPU time measures command-buffer execution, not whole-device utilization. A 30 FPS frame interval is 33.3 ms; that does not make 11 ms equivalent to 33% measured system GPU utilization.

Metal reports 76.44 MiB allocated in clear scenes and 82.44 MiB in storms. This overlaps the process's unified-memory footprint; do not add the two numbers. RSS alone understates the measured physical footprint.

## Covered desktop optimization

| Actual fully covered desktop startup | Before | After |
|---|---:|---:|
| CPU (% of one core) | 0.356 | 0.116 |
| Process wakeup counter rate (per second) | 4.10 | 0.70 |
| Physical footprint (MiB, median) | 18.30 | 18.19 |
| Submitted rendering frames | 0 | 0 |

The host previously queried desktop coverage every 0.25 seconds even when rendering was completely paused. It now uses a 2-second fallback while fully covered: eight times fewer scheduled coverage queries. Narrow visible strips retain 0.25-second tracking and normal visible rendering retains 0.75-second tracking. Occlusion notifications refresh coverage immediately; a rebuild guard prevents callbacks from reviving detached surfaces. If a reveal produces no notification, the slower fallback can delay detection by roughly two seconds plus timer tolerance. Actual Space/display/reveal latency still needs interactive verification.

This is one paired 24-second test with the first eight seconds excluded. The small idle memory figures apply to **startup before scene targets are allocated**. A previously visible paused app retains rendering resources; this test does not establish its retained memory. The wakeup rate is the sum of `proc_pid_rusage` package-idle and interrupt wakeup counters, not a count of whole-system physical wakes.

## Experiments and safeguards

Separate profiling identified wave simulation, cached sky/cloud rendering and the ocean surface as major GPU costs. Profiling changes execution and its stage times can overlap; they must not be summed or substituted for unprofiled timings.

- Skipping direct-light work at zero celestial illumination showed no clear gain in exploratory runs and was reverted.
- Skipping zero spectral coefficients changed signed-zero bit patterns in the strict FFT comparison and was reverted.
- Caching quantized wave frequencies changed float32 FFT values (maximum observed error about `5.72e-6`) and was reverted.

No experimental shader, frequency table, new buffer, quality reduction or effect is retained. The FFT oracle now also covers sparse inputs and negative zero: all 24 pattern/phase cases pass with zero numeric or bit differences. Matched daylight, starry night and storm night have identical HDR and final display bytes to the saved baseline. Native compilation, all CPU suites and the windowless startup/recreated-surface regression passed.

## Reproduce and interpret

```sh
zsh macos/build.sh
python3 macos/Tests/benchmark_resources.py --out macos/build/resources
# Separate diagnostic run; do not compare profiled timings to normal timings:
python3 macos/Tests/benchmark_resources.py --profile --out macos/build/resources-profile
```

The resource harness uses fixed local coordinates and UTC fixtures with providers disabled, creates zero windows, records 360 frames, excludes 60 GPU warmup frames and the first three seconds of process samples, and samples `proc_pid_rusage` at 4 Hz. CPU times are converted from Mach ticks with `mach_timebase_info`; the conversion was checked against a busy child process's CPU clock. CPU 100% means one core, not the entire M1. Use `--app` for a saved baseline bundle and alternate repeated baseline/updated runs before claiming an active-rendering improvement.

To measure covered startup, keep the desktop fully covered for the test:

```sh
python3 macos/Tests/benchmark_covered_desktop.py \
  --app macos/build/Ocean.app --out macos/build/resources-covered
```

This command opens one background wallpaper process, samples it, then terminates that process. It fails rather than reporting idle savings if diagnostics show rendering. It uses a fixed scene with network providers off and does not change saved app preferences.

Active tests exclude WindowServer/display presentation and provider refresh costs. They do not measure actual multi-display overhead, system-wide GPU utilization, watts or battery life. Power counters require superuser access and were unavailable in this session. Short samples, changing background load and unrecorded power/thermal conditions limit timing comparisons. See [testing methodology](testing.md) and [remaining desktop checks](wallpaper-host.md).
