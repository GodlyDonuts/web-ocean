# PR 2 cleanup validation — 6 November 2026

The PR is narrowed to the native desktop host, conservative adaptive rendering and current-scene verification. See [the scope and manual-test matrix](wallpaper-host.md). All newly introduced decorative sky events, wildlife, waterspouts, optical effects and eclipse rendering are removed; existing ocean/weather/stars and Sun/Moon behavior are restored from main.

## Local results

On the Apple M1 development Mac:

- Native build and all 10 CPU suites passed, including visibility strips/gaps and actual full rectangle coverage.
- The maintained GPU regression suite passed 13 daylight scenes, 18 weather scenes, 13 night-water scenes, 12 viewport-shape checks and three headless lifecycle captures plus benchmark/startup-failure smoke tests.
- Eight failure-injection tests passed: failed processes, stale or absent reports, bad timing samples and GPU errors cannot silently produce a successful gallery.
- The new startup fixture passed diagnostics before any frame/scene allocation, followed by a real GPU render and replacement-view sizing with unchanged HDR dimensions. No windows were created.
- The gallery passed all 12 retained core scenes and three validated unprofiled benchmarks. No historical captures or decorative effects are needed.
- Matched noon, starry-night and storm-night HDR and final display bytes are **identical** to a separately built main baseline, commit `514060e689877abd97cd9ad3980ab6656428c0ca`.
- The maintained documentation/resource inventory, Python/shell syntax and whitespace checks passed.

The original composite fragment is preserved literally; the additional display fragment reuses its arithmetic with mapped sampling. This avoids small rounding differences introduced by the initial PR's display-transform refactor.

An actual desktop launch exposed a diagnostics crash when the fully covered wallpaper had not yet allocated its sky cache. Logging now tolerates that state and avoids reading unwritten uniforms. The repaired covered-desktop launch survived repeated diagnostic ticks with zero submitted frames, zero measured GPU time and no errors. Menu accessibility automation timed out, so interactive controls, actual reveal/hot-plug, mixed monitors and installed Open at Login are **not claimed verified**. The temporary live process was stopped after the check.

[Local regression summary](pr2-cleanup-report-2026-11-06.json) · [Exact scene parity evidence](pr2-scene-parity-2026-11-06.json).

## CI and remaining scope

The PR workflow runs on a supported arm64 macOS label, rejects Intel runners explicitly, runs windowless regressions and requires valid gallery benchmarks. It does not repeatedly launch desktop windows or treat a process-alive screenshot as proof of correct wallpaper presentation. Consult the PR's current checks for hosted status.

Gallery timings are local command-buffer samples, not a matched performance-improvement claim or a battery measurement. Real OS/multi-display/power/login verification remains in [the desktop host matrix](wallpaper-host.md).
