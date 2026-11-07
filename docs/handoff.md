# Developer handoff — 4 November 2026

## What to continue

The active implementation is `macos/`, a Swift/AppKit/MetalKit host and native Metal renderer. The app now has desktop wallpaper windows and shared HDR presentation, with `--preview` retaining the resizable development window. Actual multi-monitor, installed login and OS reveal behavior still need manual verification; see [the desktop host](wallpaper-host.md). `main` contains the accumulated Metal implementation, assets, research, tests and evidence. The old browser-host branch `feature/native-macos-wallpaper` predates this implementation; do not treat it as the next version of the app.

The original main had only the WebGPU renderer and MIT license. The native work was accumulated locally before this publication. Main is advanced with normal commits, preserving that ancestry; there is no need to delete the branch or rewrite its history to publish this snapshot.

## First session

1. Read the root [README](../README.md) and [architecture](architecture.md).
2. Build with `zsh macos/build.sh`. It compiles Swift, packages all shader sources/assets and ad-hoc signs `macos/build/Ocean.app`.
3. Run `zsh macos/test-current.sh` after installing the optional [Python dependencies](../requirements-dev.txt). This is the current GPU/CPU handoff gate. For a CPU-only environment, use `zsh macos/test-unit.sh`.
4. Open the app with `--preview` once for visual review. Compare clear day, sunrise/sunset, moonlit and moonless nights, storm buildup, rain, raised wave crests, and narrow/full-screen windows.
5. Read [the roadmap](engineering-roadmap.md) and pick one scoped change. Preserve a matched baseline build in an ignored directory if comparing appearance or performance; archive artifacts are not fetched automatically by tests.

Use `git status` before and after work. Build products, Python environments, captures, logs and Cargo targets are ignored. Source, packaged assets, optional tooling, documentation and curated evidence are committed. Do not commit local location/weather caches or machine credentials.

## Product constraints

- Fixed view looking across the ocean; no free camera or navigation UI.
- Native Metal for simulation and rendering. The retained HTML renderer is a reference, not the production runtime.
- Local daylight and weather should follow the user. Use approximate IP location without asking for coordinates or opening a GPS permission prompt.
- Keep transitions continuous. Wind changes should preserve wave phase and accumulated cloud/detail advection.
- Nights should feel like remote ocean with no city glow, while retaining visible wave shape and plausible foam/cloud layering.
- Performance is a product requirement. Keep bounded pixels, mesh density, caches and frame submission. Queue at most one frame; stop work when the preview has no visible consumer.
- Automated checks must not repeatedly open or close windows. `--verify` and `--benchmark` are offscreen with prohibited activation and `windowCount == 0`. The desktop visibility probe requires explicit interactive opt-in.

## Current state and recent fixes

The app has six-cascade FFT waves, persistent foam clipmaps, volumetric low clouds, high wisps, environment reflections, geometric rain particles, lightning/mist and continuous weather-driven sea state. A NASA/Gaia-derived galaxy asset ships locally; 12,000 analytic point sprites provide resolved stars.

Astronomy uses daily cached solar timings and hourly celestial samples. Sun and Moon move independently; UTC is independent of the wave phase. Approximate IP location is cached for 24 hours. Weather uses cached Open-Meteo conditions and smooth state transitions. See [day/night](day-night-cycle.md) and [weather](dynamic-weather.md).

The latest appearance work separates the camera's dim night backdrop from the cinematic illumination of water/clouds; suppresses stars through clouds; and fades galactic contrast with cloud cover. The storm-water fix extends the near guard geometry behind the eye, corrects raised-crest footprints/Fresnel, lights foam consistently, removes foam on wave undersides and handles submerged backgrounds. See [waterline details](night-water-fix.md). The camera's low-height override is verification-only.

At 1280×800 the mesh has 98,304 triangles. The pixel budget is approximately 1.024 million; 30 FPS is the default. Sky cache dimensions are half the internal viewport, refreshed up to 8 Hz. Environment cube faces refresh incrementally at up to 10 Hz. The weather camera-surface probe uses one GPU thread and a 16-byte buffer in the existing encoder. These bounds are not universal battery-life guarantees.

## Next milestones

1. **Shared world ownership.** Separate simulation and shared environment resources from per-surface color/depth/postprocess targets. Start from `SharedSurfaceDemand.swift` and the pure layout/demand tests. Do not duplicate the whole simulation per monitor.
2. **Presentation and reveal.** Establish real OS visibility behavior, hidden-time recovery and consistent reveal frames. Current pause behavior is implemented; elapsed-time recovery and multiple consumers need explicit design and GPU evidence.
3. **Wallpaper integration.** The first desktop host and settings now exist; verify multi-display/Spaces/reveal behavior and installed login registration. The historical WebKit host is reference material, not a drop-in Metal solution.
4. **Regional rendering.** Implement only after accounting for displaced geometry, foam advection, reflections and bloom support. A screenshot scissor does not prove upstream GPU work is saved.
5. **Visual/performance refinement.** Use persistent animation captures and matched measurements, with clear error budgets for FFT resolution changes, temporal reconstruction, density caching and foam formats.

The [engineering roadmap](engineering-roadmap.md) contains detailed gates and rejected experiments. The supplied research kit is reference evidence; its original commands and workload counts do not override current implementation constraints. Imported scripts may default to interactive windows, while adapted project diagnostics default to windowless operation.

## Evidence and interpretation

Curated JSON, PNG and MP4 evidence is under `docs/`; generated raw textures, complete local baseline app bundles and all benchmark runs live under ignored `macos/build/`. Reports dated 23 October describe earlier optimizations; 30 October reports describe subsequent clouds/weather/night work. File presence is not a fresh pass: consult [validation for this handoff](validation-2026-11-04.md).

Some historical comparisons deliberately require local `Before.app` bundles or obsolete image snapshots. They are not fresh-clone prerequisites. The maintained night-water test runs without any saved before captures; a historical comparison is generated only when those captures exist. Historical exact-image checks against pre-waterline geometry have been removed from the broad test runner, while current isolated equivalence checks remain.

CI builds the browser reference, verifies repository links/shader inventory, builds the native app and runs CPU tests. Metal runtime validation and cinematic quality must be checked on an actual supported Mac. CI success alone does not establish rendering correctness, frame pacing, total-system energy or desktop behavior.
