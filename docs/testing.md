# Build, tests and visual review

## Requirements

Build/run: Apple silicon Mac, macOS 13+, Xcode Command Line Tools and Metal support. The native app has no package-manager dependencies. Python scripts require Python 3; image-analysis scripts additionally use NumPy and Pillow from `requirements-dev.txt`. Imported research plot regeneration separately requires Matplotlib; `research/2026-10-30-ocean/requirements.txt` lists its dependencies. Storm movie generation uses `ffmpeg` on PATH and is optional.

```sh
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements-dev.txt
```

Use `zsh macos/build.sh` after changes to Swift, shaders, the manifest or packaged assets. Editing a shader source without rebuilding/copying the app resources does not update a running app's retained pipelines. For final interactive review, reopen the app once after building; use `--preview` for a development window.

## Maintained gates

| Command | Purpose |
|---|---|
| `python3 tools/check-repository.py` | Verify maintained documentation links and packaged shader/asset inventory |
| `zsh macos/test-unit.sh` | CPU weather/provider, astronomy/location, motion, clock, layout, mesh and shared-demand contracts |
| `zsh macos/test-current.sh` | Build, CPU contracts and current GPU daylight/weather/night-water/coverage/headless gates |
| `zsh macos/test.sh` | Broader development suite, including current isolated FFT/filter equivalence, clouds, time, resources and texture-usage checks |
| `zsh macos/test-daylight.sh` | Build, astronomy/provider CPU checks, day/night and GPU celestial motion, stellar resources |
| `zsh macos/test-weather.sh` | Build, weather CPU/provider tests and GPU weather fixtures |
| `python3 macos/Tests/verify_night_water.py` | Storm phases, raised crests, foam, rain, clear/day/portrait and synthetic low-eye-height submerged scenes |

Except scripts that build explicitly, GPU scripts require `macos/build/Ocean.app` to exist. The current handoff gate is the recommended starting point. The broader suite takes longer and produces substantial disposable readbacks; use targeted checks while developing.

GPU fixtures call the app binary with `--verify`; benchmarks use `--benchmark`. Both modes prohibit activation, create zero `NSWindow`s and read offscreen GPU output. Do not substitute visible app launches in a loop. Deterministic local-coordinate fixtures do not need provider network access or update the user's saved astronomy state. Metal API/shader validation is enabled by the current suite for daylight/weather; night-water enables it itself. Debug validation is not a performance measurement.

## Captures and interpretation

Generated artifacts are under ignored `macos/build/` subdirectories. `--query` supplies URL-style `key=value&key=value` settings; quote the whole argument in the shell. Useful deterministic controls include `fixedDt`, `time`, `dayNight`, `latitude`, `longitude`, `timeZone`, `utc`, `heading`, `storm`, `rainParticles`, `renderWidth`, `renderHeight` and `dump`.

```sh
macos/build/Ocean.app/Contents/MacOS/Ocean --verify \
  '--query=dayNight=1&latitude=40.7128&longitude=-74.006&timeZone=America/New_York&utc=1794283200&storm=1&fixedDt=0&time=60&dump=macos/build/storm-check'
```

`dump` writes tightly packed HDR RGBA16F and `.bgra8` display bytes. Other diagnostic options write mips, cloud/environment, bloom or waterline state. Do not interpret raw files as PNGs. A GPU scene being finite and nonconstant is necessary but does not prove visual realism; inspect the display captures and animated transitions.

Review dawn/day/dusk, moonlit and moonless nights, clear and broken clouds, storm buildup, rain occlusion, foam on raised wave crests, overtaking waves and portrait/ultrawide views. Check normal animation, resize/full screen and pause/reveal behavior. Pure demand tests do not establish real OS desktop visibility or completed multi-display presentation.

## Historical comparisons

`compare_quality.py --shared-cubic` and `--fused-evolution` isolate current equivalent paths and remain in the broad suite. Bare `compare_quality.py` and `--historical-geometry` compare archived surface/geometry revisions. Later intentional visual changes invalidate exact-image equality against those historical shaders, so those two commands are retained for investigation but removed from the broad current runner.

`verify_cinematic_night.py`, `benchmark_cinematic_night.py` and some other historical scripts need a separately saved baseline app or prior captures. They do not automatically reconstruct a baseline from Git. Read each script's CLI and required paths. `verify_night_water.py` has no baseline dependency: it only generates a before/after montage when optional `before-60.png` and `before-90.png` captures already exist.

Reports and movies committed under `docs/` are dated evidence, not automatically refreshed results. Never overwrite an older report with a new run without describing the revision, scene and scope. Fresh verification artifacts stay in `macos/build/` unless intentionally curated for a change.

## Performance

Measure normal unprofiled command-buffer times after warmup, using the same resolution, weather/time, frame count, cadence, power state and baseline/updated ordering. Save an explicit baseline app bundle before changing resources. Run benchmarks sequentially; simultaneous GPU tests contaminate timing. Compare ABBA or alternating runs rather than a single instantaneous diagnostics sample.

`python3 macos/Tests/benchmark.py --help` describes isolated baseline modes. Several preserve historical appearances, so label differences clearly; they are not all equivalent-quality comparisons. Record mean/median/P95, CPU encode time and allocations separately. Whole-system energy, WindowServer behavior and reveal latency need separate measurements. Lower GPU time alone does not prove longer battery life.

`python3 macos/Tests/benchmark_resources.py` records process CPU, physical footprint, wakeup counters and Metal allocation alongside renderer timings without root. `benchmark_covered_desktop.py --app macos/build/Ocean.app --out macos/build/resources-covered` opens one temporary desktop process and requires zero submitted frames before reporting covered-startup usage. See the [dated resource report](resource-usage-2026-11-06.md) for reproduction commands, measured savings and scope limits.

CI deliberately runs native compilation and CPU tests without assuming a hosted GPU. The browser CI job installs npm dependencies and rebuilds the reference artifacts. Real Metal validation and interactive wallpaper behavior require a supported Mac.

## Desktop host regression checks

`PerformancePolicyTests` checks sub-grid visible strips/gaps as well as exact full rectangle coverage. `python3 macos/Tests/test_render_gallery.py` injects failed processes, stale/missing reports, nonfinite timings and invalid GPU diagnostics; any benchmark failure must fail the gallery. `python3 macos/Tests/render_gallery.py` captures the core ocean scenes and validates three benchmarks, with no saved baseline required.

After building, run the offscreen startup/recreated-view fixture with `python3 macos/Tests/verify_wallpaper_lifecycle.py` (also part of `test-current.sh`), or the sizing-only diagnostic:

```sh
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 macos/build/Ocean.app/Contents/MacOS/Ocean --verify '--query=fixedDt=0&dayNight=0&testSurfaceSizing=1'
```

The fixture creates a replacement MTKView with an intentionally wrong drawable size while retaining the shared HDR dimensions, and checks that the budget is applied. It creates no window. [Desktop host verification](wallpaper-host.md) distinguishes this test from actual display hot-plug and login behavior. The GPU workflow uses a supported arm64 runner and runs windowless checks; it does not automatically place wallpaper windows on a desktop.
