# Ocean

A cinematic ocean being developed into a live macOS wallpaper. The current app uses **Swift, AppKit, MetalKit and Metal**, with a fixed view across the water. Waves, volumetric clouds, rain, sunlight, moonlight and stars respond to time and weather.

**Start here:** [developer handoff](docs/handoff.md) · [architecture](docs/architecture.md) · [testing](docs/testing.md) · [next work](docs/engineering-roadmap.md).

![Native nighttime ocean](docs/night-sky-integration-preview.png)

## Current status

`main` is the current native Metal implementation. The root HTML/JavaScript renderer is retained as a browser reference. The separate historical `feature/native-macos-wallpaper` branch and its browser-host implementation predate the Metal rewrite.

| Capability | Status |
|---|---|
| Fixed ocean viewpoint, animated waves, foam and reflections | Implemented |
| Native Metal rendering, bounded resolution, 30 FPS default | Implemented |
| Volumetric clouds, scene-space rain, gradual storm transitions | Implemented |
| Local sunrise/sunset, independent Sun/Moon motion, remote starry sky | Implemented |
| Approximate IP location, cached weather and offline fallback | Implemented; no GPS permission prompt |
| Desktop wallpaper behind icons on every display and Space, menu bar controls, Open at Login | Implemented (`open macos/build/Ocean.app`; `--preview` for the old window) |
| Pause when covered, display/system sleep, lock, screensaver, inactive session or manual pause | Implemented |
| Adaptive governor: frame rate and pixel budget follow battery, Low Power Mode, thermal state, display refresh and desktop coverage | Implemented; see [`PerformancePolicy.swift`](macos/PerformancePolicy.swift) |
| Aurora arcs, meteor showers (real annual calendar) and bioluminescent surf, scheduled per local night | Implemented; see [`AURORA.metalinc`](macos/Shaders/AURORA.metalinc), [`NightEffects.swift`](macos/NightEffects.swift) |
| Crepuscular sun rays, 22° ice halos and sun dogs in cirrus (sun and moon), primary/secondary rainbows (moonbows at night) in sunlit rain | Implemented; see [`SHAFTS.metal`](macos/Shaders/SHAFTS.metal), [`AURORA.metalinc`](macos/Shaders/AURORA.metalinc) |
| Real solar and lunar eclipses on their actual dates and places (Meeus lunar terms): Moon covers the Sun, corona at totality, copper umbra | Implemented; see [`CelestialCycle.swift`](macos/CelestialCycle.swift), [`SKY_BG.metal`](macos/Shaders/SKY_BG.metal) |
| Great comets: rare two-week apparitions with coma, curved dust tail and blue ion tail pointing away from the Sun | Implemented; see [`AURORA.metalinc`](macos/Shaders/AURORA.metalinc), [`NightEffects.swift`](macos/NightEffects.swift) |
| Noctilucent clouds (summer twilight, 50–70° latitude) and the green flash on the last solar limb | Implemented; see [`AURORA.metalinc`](macos/Shaders/AURORA.metalinc), [`SKY_BG.metal`](macos/Shaders/SKY_BG.metal) |
| Gull flocks at dawn/dusk (vertex-generated, flapping/gliding) and storm waterspouts, both on deterministic schedules | Implemented; see [`BIRDS.metal`](macos/Shaders/BIRDS.metal), [`NightEffects.swift`](macos/NightEffects.swift) |
| Storm waves passing the camera and night foam correction | Implemented and GPU-tested |
| Shared multi-display renderer | Implemented: one simulation and HDR frame, cheap per-display composite (`fs_mirror`) |

The objective is a lightweight, continuous wallpaper with real local daylight and weather, a fixed ocean composition, and cinematic nights without city light pollution. Inland weather drives an idealized sea state; it is not a marine swell forecast.

## Build and run

Use an Apple silicon Mac with macOS 13+ and Xcode Command Line Tools:

```sh
git clone https://github.com/GodlyDonuts/web-ocean.git
cd web-ocean
zsh macos/build.sh
open macos/build/Ocean.app
```

No npm packages, Python, Rust, development server or downloaded assets are required for the native build. Swift builds the app bundle; packaged Metal sources compile into retained pipeline states at startup. The included galaxy asset is ready to use. See its [credits and provenance](macos/Assets/Galaxy/CREDITS.md).

The app runs as a wallpaper with a menu bar (wave) icon: pause, daylight/weather, frame rate (Adaptive/60/30/20/15), quality budget, displays and Open at Login. `macos/build/Ocean.app/Contents/MacOS/Ocean --preview` opens the resizable development window instead. The camera remains fixed. Night events can be forced for previews with `--query=aurora=2&meteors=40&bio=1` (0 disables); `shafts=0` disables sun rays; `birds=0.5` / `spout=1` force a gull flock or waterspout (0 disables); `nlc=1` forces noctilucent clouds in deep twilight; `comet=1` forces a comet apparition.

`python3 macos/Tests/render_gallery.py` renders a windowless scene gallery plus day/night-effects GPU benchmarks; the `GPU gallery` workflow runs it, the unit tests and a live wallpaper smoke test on GitHub's macOS runner on every push.

The preview caps its internal image at approximately 1,024,000 pixels, preserves aspect ratio and defaults to 30 FPS. The standard 1280×800 view uses 98,304 ocean triangles. Wave simulation updates six periodic 256×256 FFT bands; these are reusable wave tiles rather than a fully meshed world. Geometry is concentrated in the viewport with sparse displacement guards, including a near patch behind the camera that prevents holes during overtaking storm waves.

## Check the current implementation

The native build has no test dependencies. Some GPU analysis scripts need Python with NumPy and Pillow:

```sh
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements-dev.txt
zsh macos/test-current.sh
```

This maintained handoff gate builds the app, checks CPU contracts, and validates daylight, weather, night-water rendering, mesh coverage and the windowless lifecycle. It takes several minutes and writes disposable captures to ignored `macos/build/` directories. GPU fixtures use synthetic coordinates and do not perform IP lookup or write user astronomy caches. They create **zero application windows**.

For a quick CPU-only check, run `zsh macos/test-unit.sh`. For the broader development suite, run `zsh macos/test.sh`. [Testing instructions](docs/testing.md) distinguish maintained regressions, optional visual reviews, historical comparisons and performance measurements. CI builds native sources and runs CPU checks; hosted CI is not a substitute for real Mac GPU validation.

## Time, location and weather

The app looks up coarse location by public IP through `ipwho.is`, reuses it for astronomy and weather, and caches the result. Weather comes from Open-Meteo. Normal operation can therefore contact those services; neither is required for the deterministic GPU fixtures. No account or API key is required by the current implementation.

Solar timings and hourly celestial samples are cached daily; real UTC drives the sky independently of wave phase. The Moon has its own path and phase. Weather is cached for 15 minutes and transitions continuously; IP location is refreshed infrequently, with a 24-hour cache. Saved state lives under `~/Library/Application Support/OceanWallpaper/`. Offline operation retains available cached state. See [day/night details](docs/day-night-cycle.md) and [weather behavior](docs/dynamic-weather.md).

## Where to work

| Area | Source / guide |
|---|---|
| Window lifecycle and menus | `macos/main.swift` |
| Resource ownership and frame encoding | `macos/OceanRenderer.swift` |
| Wave simulation, surface, foam, rain and sky | `macos/Shaders/` and [architecture](docs/architecture.md) |
| Astronomy and IP location | `macos/CelestialCycle.swift`, `macos/ObserverLocationProvider.swift` |
| Weather state and providers | `macos/Weather.swift`, `macos/WeatherProvider.swift` |
| Animation timing | `macos/AnimationClock.swift` |
| Display demand contracts and diagnostic | `macos/SharedSurfaceDemand.swift`, `macos/Diagnostics/` |
| Tests and experiments | `macos/Tests/` and [testing guide](docs/testing.md) |
| Research and evidence | `research/`, `docs/` and [documentation index](docs/README.md) |
| Optional shader migration tools | `tools/`; these are not part of normal native builds |
| Retained browser reference | `index.html`, `js/`, `ocean.html`, `ocean.min.html` |

## Continue development

Read [the handoff](docs/handoff.md) before changing render architecture. The next milestone is to separate shared ocean/environment state from display surfaces, validate presentation demand and reveal behavior, then integrate desktop wallpaper windows. Preserve the current fixed view, no-prompt IP location, continuous transitions, bounded GPU work and windowless automated tests.

Current limitations include approximate lunar positioning, procedural resolved stars, approximate cloud multiple scattering, a height-field underwater treatment, and no shoreline or overturning breakers. Startup shader compilation and reduced internal resolution are deliberate tradeoffs. Performance reports in `docs/` identify their scenes and revisions; compare matched before/after runs rather than combining timings from different versions. The latest storm-water correction measured about 10.62 → 10.58 ms mean GPU time in a short M1 comparison; this is not a battery-life claim.

![Storm wave coverage correction](docs/night-water-comparison.png)

## Browser reference

Node.js and npm are optional for the retained browser version:

```sh
npm ci
npm start
```

Open the local URL printed by the server in a browser with WebGPU support. `npm run build` regenerates the standalone HTML artifacts. Browser controls and rendering behavior are historical reference material; the native app has no free camera. Do not run the shader-export tools over hand-edited Metal without reviewing the diff: native Metal is the active source of truth.

## Origins and license

The original WebGPU renderer was built with Claude Code (Opus 5.5). This project extends it into a native macOS ocean wallpaper. Code is MIT licensed; see [LICENSE](LICENSE). NASA/Gaia-derived imagery has separate [credits and usage guidance](macos/Assets/Galaxy/CREDITS.md). Imported research retains its original files and attribution under [research/](research/README.md).
