# Archived renderer development notes

Historical README snapshot through 30 October 2026. Some commands compare obsolete appearances or require local baseline app bundles. Use the current [README](../README.md), [handoff](handoff.md), and [testing guide](testing.md) for maintained entry points. Measurements below describe the revisions named alongside them.

# Ocean

A cinematic, animated ocean being developed into a live macOS wallpaper. The macOS app is written in **Swift and Metal Shading Language**, using AppKit and MetalKit. It renders directly to an `MTKView`; it does not embed a browser or execute HTML, JavaScript, WGSL, or WebGPU.

The original WebGPU renderer is retained as a browser reference. These screenshots show that original renderer:

![Looking toward the sun from 2.4 m above the water](../docs/front.jpg)

| 75 degrees off the sun, 2.4 m up | Looking toward the sun from 30 m up |
|---|---|
| ![](../docs/side.jpg) | ![](../docs/high.jpg) |

## Project objective

Create a macOS wallpaper that feels like a living ocean outside the user's window, with realistic moving waves and local daylight and weather.

The [engineering roadmap](../docs/engineering-roadmap.md) reconciles the supplied research with the current Metal renderer. The next architectural focus is one shared world per coherent environment, backward visibility demand, and postprocessing whose support is explicit. A [static visibility diagnostic](../macos/Diagnostics/README.md) is available with a windowless default; desktop tiles require an explicit `--present` invocation.

- **Fixed ocean view:** A set viewpoint looking across the ocean toward the horizon. No free camera, mouse-look, or navigation controls in the macOS app.
- **Always moving ocean:** Animated waves, foam, reflections, and clouds.
- **Real local sun cycle:** Calculate and cache the sun's position from approximate IP location, date, and time. Sunrise and sunset should match local conditions, including seasonal changes, with transitions through dawn, day, dusk, and night.
- **Matching local weather:** Reflect local rain/showers, cloud cover, wind/gusts, rough seas, fog and thunder, with smooth changes between updates and a continuous drizzle-to-hurricane preview control.
- **Shared displays and demand:** Share wave/environment resources across displays, combine visible consumers conservatively, and submit no recurring GPU work when every surface is hidden. Regional shading must include bloom, reflection, displacement, and foam-advection dependencies.
- **Desktop integration:** Eventually run behind desktop icons as a wallpaper, with settings suited to continuous background use.
- **Location and connectivity:** Use an infrequent IP lookup for approximate location, cache daily solar timings locally, and retain saved location while offline. Local weather is cached for 15 minutes and retained while offline.

**Implemented:** the native Metal ocean preview, fixed viewpoint, bounded rendering workload, and a conservative pause policy covering occlusion, minimization, system/display sleep, and inactive sessions. The visibility diagnostic and shared-demand contracts are implemented; a shared multi-display Metal renderer, regional rendering and desktop wallpaper integration remain planned. Local weather and continuous storm transitions are implemented; see [dynamic weather](../docs/dynamic-weather.md). Cached local daylight, independent sun/moon paths and a cinematic remote night sky are now implemented; see [the day/night cycle](../docs/day-night-cycle.md).

## Run the macOS app

Requires an Apple silicon Mac, macOS 13 or later, and Xcode Command Line Tools. From this directory:

```sh
zsh macos/build.sh
open macos/build/Ocean.app
```

If Node.js is installed, `npm run macos` builds and opens the same app. The native build needs no npm packages, development server, Rust installation, or browser. Metal shader sources ship in the app and are compiled by the system Metal compiler at startup, then retained as pipeline states.

The window is resizable and supports full screen through the green window button or Control-Command-F. Close it or press Command-Q to quit. The ocean viewpoint remains fixed.

Wave phase follows the renderer's intended ten-minute cycle. Cloud motion, gusts, and foam detail continue across that boundary. Their coordinates stay bounded through periodic texture offsets and integer noise-grid origins, while the CPU tracks elapsed time in double precision.

The default is 30 FPS and at most approximately 1,024,000 internal pixels, preserving the window's aspect ratio. Retina and full-screen windows scale that image to the display. Rendering pauses when the window is minimized, fully covered, or the Mac sleeps; at most one frame is submitted at a time.

### Diagnostics and GPU verification

```sh
macos/build/Ocean.app/Contents/MacOS/Ocean --diagnostics
```

Every five seconds this reports the native renderer, GPU, completed frame count, actual FPS, GPU execution time, resolution, triangle count, pause state, and command errors. Startup includes shader compilation and initialization, so measure steady-state performance separately.

Renderer settings can be overridden at launch for repeatable comparisons:

```sh
macos/build/Ocean.app/Contents/MacOS/Ocean --diagnostics '--query=fps=20&sunElev=8&windSpeed=12'
```

Supported overrides: `fps`, `sunElev`, `sunAzim`, `windSpeed`, `windDir`, `swellHs`, `choppy`, `turbidity`, `foam`, `exposure`, `bloom`, `haze`, `clouds`, `veil`, and `dbg`. These are launch-time development settings. The Weather menu controls live local weather and storm previews; `storm=0...1` selects an immediate synthetic preset for offscreen fixtures.

To build and run the GPU integration check with Metal API and shader validation enabled:

```sh
npm run macos:verify
```

Or, after building, without Node.js:

```sh
MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1 macos/build/Ocean.app/Contents/MacOS/Ocean --verify
```

Automated `--verify` and `--benchmark` runs render offscreen with no application windows, Dock activation, or desktop focus changes. A timer drives the same Metal passes into a private BGRA8 texture; the normal preview still uses its Metal drawable. Tests assert offscreen mode, zero windows, and the prohibited activation policy. `--diagnostics` opens the regular interactive preview. For an intentional visual inspection of a single automated run, `--windowed-test` opts back into a visible window.

The check renders eight frames, reads back all six displacement, derivative, and slope-moment layers, the HDR scene, and the final display image, and rejects nonfinite or empty results. It reports Metal command errors and exits after verification. Validation instrumentation makes this mode substantially slower; use ordinary diagnostics for performance measurements.

## What is actually rendered?

At the standard 1280-by-800 internal resolution, the native renderer uses a **256-by-192 projected grid: 98,304 triangles**. Grid columns and rows scale with internal width and height, preserving the same or greater per-pixel mesh density on ultrawide and portrait displays. It projects screen coordinates onto the ocean plane, displaces those vertices with the wave simulation, and draws the result. Most vertices are concentrated inside the viewport and its immediate 15% margin. Sparse outer bands extend farther sideways and below the screen. For views narrower than 1:2, two additional compute reductions measure conservative per-frame displacement bounds across all six wave cascades. The horizontal guard band then expands in world units, including the effect of displacement on view depth. This keeps lateral wave motion from moving a thin ocean strip out of the viewport. The central grid and triangle count stay unchanged. A separate guard shader pipeline keeps the historical normal-view arithmetic intact and is selected only for narrow views. The top of the mesh approaches the horizon. There is no surrounding world quadtree in the native app, and no ocean mesh behind the camera.

The original browser renderer instead selects visible patches from a CDLOD quadtree reaching 160 km. It already performs frustum culling; it never draws that entire surrounding ocean at full detail. The native projected grid reduces the approximately 394,000 triangles seen in the optimized browser preview to 98,304, about 75% fewer.

**Simulation and visibility are different:** six periodic 256-by-256 FFT wave tiles are still updated as whole tiles. Their samples describe reusable wave bands, rather than every square metre of a 160 km ocean. Cropping their FFT inputs would change the simulated waves. World-space foam uses two 512-by-512 clipmaps; expensive foam injection and advection are skipped behind the fixed camera and outside its horizontal guard band. Offscreen sky directions are still generated for reflections and ambient illumination.

## Native rendering pipeline

1. **Waves:** Tessendorf FFT simulation with six cascades, JONSWAP wind sea, directional spreading, swell, capillary dispersion, and choppy displacement. Native Metal compute kernels evolve the spectrum, run row/column inverse FFTs, and produce mipmapped displacement, derivatives, and slope moments. Evolution and the row FFT share one kernel: each lane evolves two samples directly into the original bit-reversed threadgroup arrays. This removes one dispatch, 12 MiB of intermediate spectrum-buffer allocations, and 24 MiB of logical buffer writes/reads per frame; equations, float32 precision, and butterfly order remain unchanged. Wave and foam mip chains each use two fused dispatches, replacing seventeen separate dispatches with four. Intermediate values retain the original half-precision texture boundaries and float32 addition order. A startup GPU probe selects the native texture-store rounding mode; unsupported results use the original chain. Mip bindings are cached between frames.
2. **Foam:** Persistent world-space foam is injected from the combined surface Jacobian, advected downwind, and decayed. A procedural foam-detail texture is generated once at startup.
3. **Atmosphere:** Transmittance and multiple-scattering lookup tables initialize once. The sky-view table and sun visibility refresh at most four times per second. Two procedural cloud layers preserve the original sky shading. Noise octaves with exactly zero filter weight skip their noise evaluation and accumulation. Coordinate updates continue to preserve the same rounding in the stable-time shader.
4. **Reflections:** A 128-pixel environment cube refreshes one face and its mip chain at most ten times per second; all faces initialize together. The slow-moving visible sky is cached at 50% of the internal render dimensions and refreshed at most eight times per second. Volumetric clouds do not evaluate the old flat-layer antialiasing edges. The retained flat-cloud reference shader variants omit those evaluations for layers disabled by the existing 0.001 enable threshold. Only variants for the launch configuration are created; the normal two-layer configuration creates no extra pipelines. Each cache refresh checks current layer enablement and uses the full shader if the specialization omits any newly enabled layer. Sky fragment shading is restricted to the visible horizon region plus a conservative margin. Wave-bounded guard geometry lets narrow views use the same sky-work rejection as normal views.
5. **Ocean:** A viewport-projected mesh samples the waves. Continuous ray-derived texture footprints and cubic reconstruction of the two coarsest bands avoid the previous grid-like shading artifacts. Slope moments determine anisotropic roughness and sun glitter. Their previously unused fourth channel now stores the cross derivative, so fragment shading reads two wave textures per cascade instead of three. It preserves the original half precision and filters; displacement remains available for geometry and foam. Cubic and gradient texture reads are skipped when their blend weight is zero, preserving the transition and output. The derivative and moment textures share cubic sample positions and weights; each texture retains its original taps, interpolation order, and precision.
6. **Post-processing:** HDR rendering with 4x MSAA, six-level bloom, AgX tone mapping, white balance, and dithering. Apple GPU tile memory holds transient multisample color and depth targets; only the resolved HDR image is stored.

The resolved HDR scene, visible sky cache, and six bloom textures declare only render-target and shader-read usage. Compute-write and pixel-format-view permissions are omitted for these eight textures. This follows [Apple’s texture optimization guidance](https://developer.apple.com/documentation/metal/optimizing-texture-data) and allows the driver to select lossless compression where supported; simulation textures retain their required compute-write access. Memoryless MSAA and depth attachments remain render targets only.

Swift manages resources and frame submission; all simulation, shading, and post-processing run in Metal. Fixed camera matrices and launch-time settings are cached; ordinary frames update only changing uniform fields. Resize invalidates those cached values. Only frame uniforms, displacement, and its sampler are bound to ocean vertices; narrow views additionally bind the guard bounds; fullscreen vertex shaders receive no resources. The immutable compute buffer-size table is bound once per encoder. Serial compute encoders preserve dependent FFT and mip order. Tracked, directly bound resources synchronize subsequent render and readback passes. Explicit compute barriers are omitted because Metal ignores them on serial encoders. A single-frame semaphore protects shared uniforms and prevents GPU queue buildup. The projected grid uses 16-bit indices when its vertex count permits, halving index storage and bandwidth; larger meshes automatically retain 32-bit indices. Indices and shader resources are reused between frames; resize recreates screen-sized targets.

## Performance

The cinematic-night revision improves galactic detail and stellar hierarchy while reducing local night GPU time from 7.74 to 7.24 ms across eight alternating runs. Daytime remains essentially unchanged. See [the current night-sky evidence](../docs/cinematic-night-report-2026-10-30.json) and [asset credits](../macos/Assets/Galaxy/CREDITS.md). Older measurements below describe earlier source snapshots.

The volumetric-cloud update adds about 0.66 ms mean GPU frame time in a short local ABBA comparison (7.09 → 7.75 ms), including the half-resolution sky cache. See [the current cloud measurements and limits](../docs/volumetric-clouds.md). The optimization history below describes the earlier flat-cloud implementation.

Current automated benchmarks run offscreen. Earlier measurements below used windowed drawables; compare baseline and optimized runs within the same mode rather than treating the mode change as a performance improvement. The offscreen lifecycle fix was checked against twelve previously saved windowed HDR/display/wave/foam captures with exact byte equality. See [the lifecycle checks and parity evidence](../docs/verification-report-2026-10-23-headless.json). Run `python3 macos/Tests/verify_headless.py` for the windowless lifecycle regression gate; optional `--windowed-fixtures PATH` compares existing captures without opening any windows.

Local observations on an M1 MacBook Pro at the default 1200-by-750-point window:

| Renderer | Internal resolution | Ocean triangles | Observed GPU time per frame |
|---|---|---|---|
| Original WebGPU native wrapper | 2400 × 1500 | ~1.79 million | ~144 ms |
| Optimized WebGPU native wrapper | 1280 × 800 | 394,240 | ~17–22 ms |
| Native Metal projected grid | 1280 × 800 | 98,304 | ~9–10 ms at 30 FPS |

An additional same-renderer optimization pass on October 23 reduced local average GPU time from 9.41 ms to 8.78 ms (6.6%), 95th-percentile GPU time from 14.30 ms to 12.67 ms (11.4%), and average CPU frame encoding from 0.808 ms to 0.726 ms (10.1%). All HDR values matched the reference in eight captured states. See [the recorded runs and limitations](../docs/optimization-report-2026-10-23.json).

A subsequent resource-binding cleanup removed 97 redundant Metal binding calls per ordinary frame before mip fusion. Eight interleaved runs showed essentially unchanged CPU/GPU times, so no frame-time or power improvement is claimed. The nine-scene quality gate now also compares final display bytes after bloom and tone mapping. See [the binding comparison and full output checks](../docs/optimization-report-2026-10-23-bindings.json).

The next pass fused wave and foam mip generation from 17 dispatches into four. Eight interleaved runs reduced average CPU encoding from 0.784 ms to 0.665 ms (15.2%) and median GPU time from 8.207 ms to 8.063 ms (1.8%). All wave/foam mip bytes and final images matched in nine scenes. See [the mip-fusion results and hardware limitations](../docs/optimization-report-2026-10-23-mips.json).

The narrow-view guard fix keeps normal-view GPU timings effectively unchanged (8.092 ms versus 8.098 ms median across eight runs). It eliminates all uncovered pixels below the sky margin in twelve coverage cases, including storms and a one-pixel-wide target. The repaired 62-by-16,384 target takes about 7.58 ms median GPU time; its broken predecessor takes 4.34 ms while omitting much of the ocean, so that comparison is a quality correction rather than a speed gain. See [the guard fix, historical image checks, and timing limits](../docs/optimization-report-2026-10-23-guard.json).

The packed cross-derivative layout reduced median GPU time from 8.08 ms to 7.16 ms (11.4%) over eight interleaved runs. Portrait and ultrawide comparisons improved by 11.4% and 11.2%. All original wave/foam channels and final images matched; the new packed channel was checked separately against the original cross derivative. See [the packing measurements and checks](../docs/optimization-report-2026-10-23-packed.json).

The continuous animation clock removes the ten-minute reset of clouds, gusts, and foam detail while retaining periodic waves. At the tested boundary, rebased sky and ocean output differ from the unwrapped reference by at most one display-value step. Cloud motion remains responsive at simulated 30-day uptime, where the naive float clock loses the tested subsecond step. Eight interleaved runs after 600 seconds showed effectively unchanged GPU timing at about 7.14 ms median. See [the clock continuity checks and limits](../docs/optimization-report-2026-10-23-clock.json).

Zero-weight cloud work rejection reduced average GPU time from 7.95 ms to 7.68 ms (3.4%) and 95th-percentile GPU time from 11.73 ms to 10.58 ms (9.7%) over eight interleaved runs. Median time was effectively unchanged. All cloud intermediates and images matched exactly in the expanded checks. See [the cloud measurements and rejected early-exit experiment](../docs/optimization-report-2026-10-23-clouds.json).

Sharing cubic-filter coordinates and weights between the two fragment wave textures reduced median GPU time from 7.17 ms to 7.05 ms (1.7%) across eight interleaved runs. The later animation path improved by 2.2% across eight runs, and portrait by 2.3% across four runs. Exact image comparisons cover twelve states, including simulated month uptime and narrow views. No CPU or energy improvement is claimed. See [the shared-filter measurements and checks](../docs/optimization-report-2026-10-23-cubic.json).

A synchronization audit removed 8–18 ignored barrier API calls per ordinary normal-view frame (10–20 for narrow views) in the pre-evolution-fusion implementation, while preserving the serial compute schedule. Sixteen interleaved runs showed effectively unchanged GPU timing and inconsistent CPU differences, so no frame-time or energy improvement is claimed. A concurrent scheduling candidate also failed to establish a useful gain and remains archived. See [the synchronization audit, comparisons, and checks](../docs/optimization-report-2026-10-23-synchronization.json).

Fusing evolution with the row FFT reduced median GPU time by about 6% in default, stable-time, portrait, and ultrawide comparisons on this M1. Sixteen synthetic input/phase tests matched 50,331,648 intermediate float32 row values bit for bit; twelve rendered states also matched all original wave/foam mip data and final images exactly. Two intermediate GPU buffers totaling 12 MiB are no longer allocated in the default path. CPU differences varied by case, and no CPU or energy improvement is claimed. The 24 MiB traffic reduction describes logical shader buffer operations, rather than measured external-memory bandwidth. See [the fusion measurements and checks](../docs/optimization-report-2026-10-23-evolution.json).

Specializing away inactive cloud antialiasing reduced clear-sky average GPU time from 6.79 ms to 6.56 ms (3.4%) and 95th percentile from 8.23 ms to 7.06 ms (14.2%) over eight interleaved runs with `clouds=0&veil=0`. Single-layer skies improved average GPU time by 1.8–2.0% across four runs each. The two-layer default was effectively unchanged. Tests after the stable-clock transition confirmed similar savings. Thirty-three exact cloud checks cover all sixteen specialization/current-layer mask combinations, single-layer month uptime, threshold values, and varied viewport shapes. No CPU or energy improvement is claimed. See [the inactive-layer AA results and rejected direct edge reuse](../docs/optimization-report-2026-10-23-cloud-aa.json).

Narrower texture usage reduced default median GPU time from 6.63 ms to 6.51 ms (1.9%) across eight interleaved runs. The exact comparison includes every bloom level, HDR/display output, wave/foam mips, and cloud intermediates across fourteen scenes and viewport shapes. Average CPU encoding increased by about 0.003–0.045 ms in the eight-run comparisons; no CPU or power reduction is claimed. See [the texture usage results and limits](../docs/optimization-report-2026-10-23-texture-usage.json).

These are development observations, rather than controlled cross-API benchmarks or guarantees. They include different geometry and scheduling choices. Native GPU command-buffer timing and WebGPU timestamp timing also have different measurement boundaries. Performance varies with scene settings, window aspect ratio, system load, and validation instrumentation. GPU time is not a measurement of total energy use.

## Optimization verification

Run `npm run macos:test` (or `zsh macos/test.sh`) for display-layout tests, Metal API/shader validation on a portrait GPU target, and deterministic image comparisons against pre-optimization fragment shading with the current vertex geometry. Eight unchanged layouts are also compared against the archived pre-guard vertex shader. Python 3 is required for the comparisons; no third-party Python libraries are needed. The layout tests include Retina, 4K/5K/8K, ultrawide, portrait, fractional backing scales, and extreme aspect ratios. Pixel dimensions retain the aspect ratio within unavoidable integer rounding and the device texture-size limit.

The shared-filter comparison isolates `sharedCubic=0` versus `sharedCubic=1` with identical renderer settings. It checks HDR values, final display bytes, and all wave/foam mips across twelve states, including both animation shader variants, a 1:16 viewport, and simulated month uptime. Run it alone with `python3 macos/Tests/compare_quality.py --shared-cubic`; it also runs in the full suite.

Run `python3 macos/Tests/verify_texture_usage.py` to isolate `narrowTextureUsage=0` versus `1`. This gate checks actual resource usage flags and requires byte-identical HDR, display, all wave/foam mips, cached sky/environment/sun, and all six bloom levels in fourteen cases. Successful captures are removed; failures are retained. `dumpBloom=1` adds packed half-float bloom readbacks only in verification mode. The gate also runs in `npm run macos:test`.

The evolution/row-FFT check runs the original two-pass chain and fused kernel against zero, impulse, random, and large signed spectra at four wave phases. It compares every float32 row bit before the column FFT or half-float stores, exposing differences that final images could hide. The isolated renderer comparison (`python3 macos/Tests/compare_quality.py --fused-evolution`) also checks twelve image states and verifies that the reference allocates 12 MiB of spectrum buffers while the fused path allocates none. Both checks run in the full suite. `fusedEvolution=0` retains the original two-dispatch path for diagnosis.

The expanded cloud check compares full-sky HDR and final display bytes, the cached sky, all six environment-cube faces at every mip level, and sun visibility exactly across nine states. It includes portrait, ultrawide, overcast/clear conditions, the clock handover, and simulated month uptime.

The inactive-layer antialiasing check (`python3 macos/Tests/verify_clouds.py --inactive-aa --cleanup`) compares the full shader with each applicable specialization, including the full fallback when a compiled variant omits a currently active layer. It checks raw HDR/display, cached sky, all environment faces/mips, and sun visibility. All sixteen compiled-mask/current-mask combinations are covered; mask values 1 and 2 represent low and high cloud layers. `pruneCloudAA=0` retains the full reference path. In verification mode only, `testCloudAAMask=0|1|2|3` forces a compiled mask to exercise fallback. Both the full and specialized stable-time shaders are retained. Successful captures can be removed with `--cleanup`; failures remain available, and old result JSON is removed before each run.

The clock checks reproduce the old ten-minute cloud jump, verify the live pipeline handover, compare cloud and full-ocean output with an unwrapped reference, and simulate one month of uptime to check subsecond motion. CPU tests check bounded detail phases through one year and independently reconstruct the cloud transforms. These are accelerated time tests rather than a physical month-long run.

The image test compares every original wave/foam data channel, HDR half-float value, and final BGRA display byte exactly across nine captured states, including a 16,384-pixel-tall target, rough/cloudy water, different wave phases, daylight, and genuine 16:9, ultrawide, and portrait GPU targets. Test-only `renderWidth`/`renderHeight` overrides let it exercise dimensions that AppKit would otherwise constrain to the attached physical display. The test additionally reads every level of all wave textures and the active foam texture, confirming both reference and fused paths execute. Before comparing the wave data, it verifies that legacy moment padding is zero and all 524,286 packed cross-derivative values per captured state exactly duplicate the original displacement channel, then normalizes that repurposed padding. Image comparisons use the original bytes without normalization. A separate twelve-case MSAA occupancy test reproduces the old gaps and requires complete ocean coverage below the sky scissor margin, including storm settings and a one-pixel-wide view. A CPU scan of the same frame's displacement readback independently checks the GPU guard bounds. These tests do not establish behavior on untested physical monitors or other GPU generations.

`npm run macos:benchmark` runs four alternating reference/optimized comparisons after a 60-frame warmup, with 120 measured frames per run. It records command-buffer GPU timings and CPU frame-encoding times under `macos/build/benchmarks/original/`. After building, `python3 macos/Tests/benchmark.py --baseline previous` compares against the earlier native implementation before index compression and mip fusion. Use `--baseline inactiveaa --rounds 2 --clouds 0 --veil 0` to compare inactive-layer AA; `--clouds` and `--veil` select the same weather values for both paths. Add `--time 600.05` to measure stable-time variants. Use `--baseline evolution --rounds 2` to isolate evolution/row-FFT fusion, or `--baseline cubic --rounds 2` to isolate shared cubic-filter calculations. Use `--baseline clouds --rounds 2` to isolate zero-weight cloud work; add `--time 600` for the stable clock path. Use `--baseline clock --time 600 --rounds 2` to compare the continuous detail path with the unwrapped reference after the old boundary. Development launch options `clock=legacy` and `clock=unwrapped` reproduce the old reset or the naive float detail clock; both are reference modes. Use `--baseline textureusage` to isolate render-texture usage flags. Use `--baseline packed` to isolate wave-channel packing. Use `--baseline guard` to compare guard behavior; `--render-width` and `--render-height` select an exact test target. Its legacy path has missing geometry in narrow scenes, so its timings do not represent equivalent image quality. Use `--baseline bindings` to isolate the reduction in redundant Metal binding calls, with mip fusion disabled in both modes; use `--baseline mips` to isolate mip fusion. Add `--rounds 2` for eight runs with reversed ordering in the second round. Reference mode uses the original full-sky shading and uncached CPU uniforms. The optimized mode retains the same resolution, simulation, frame-rate cap, and tone mapping. Local results are saved in [the optimization report](../docs/optimization-report-2026-10-23.json).

Benchmark reports distinguish wall-clock encoding duration (`cpuEncodeMeanMs` / `cpuEncodeMedianMs`) from encoding-thread CPU time (`cpuThreadEncodeMeanMs` / `cpuThreadEncodeMedianMs`). The latter uses `CLOCK_THREAD_CPUTIME_ID` and excludes time the thread spends descheduled; it still varies with CPU frequency, core selection, and driver work. The comparison report includes averages and percentage differences for all CPU and GPU timing fields under `timings`. Both CPU clocks run only in benchmark mode; these fields do not measure whole-app CPU usage or energy. The runner removes each old result before launching, and the app exits with an error if the CPU clock or report write fails.

The synchronization audit follows [Apple’s resource synchronization guidance](https://developer.apple.com/documentation/metal/resource-synchronization). Both compute encoder creation paths use Metal’s default serial dispatch type; the installed SDK header also explicitly documents that `memoryBarrier` calls on serial encoders are ignored. Switching to concurrent dispatch would require an audited dependency schedule; the archived candidate is excluded from the native app.

For identifying expensive stages, launch with `--profile`. Supported GPUs report separate compute, vertex, and fragment timings under `gpuStagesMs`. Stage work can overlap, and instrumentation adds encoder boundaries, so those values are diagnostic rather than an additive frame budget. Profiling is disabled during ordinary rendering and performance comparisons.

`zsh macos/test.sh --fft-experiment` additionally checks a register/SIMD FFT candidate against the shared-memory reference and independent double-precision DFT samples. It matched all tested output values but did not demonstrate a useful speed gain on this M1, so it remains under `macos/Tests/Experiments/` and is not shipped as the app's renderer. A shared ambient-light sample cache is also retained behind the development option `sharedLighting=1`; it matched all nine test captures exactly but showed no measurable GPU improvement on this M1, so it is disabled by default. See [the experiment results](../docs/optimization-report-2026-10-23-lighting.json). A GPU FFT rotation-table candidate and a host FFT resource-list cache were also tested. Neither demonstrated a useful improvement on this M1; the table changed some rounded transform values. Both remain archived under `macos/Tests/Experiments/`, and the production FFT and binding path retain the accepted implementation. See [the FFT experiment measurements and restoration checks](../docs/optimization-report-2026-10-23-fft-experiments.json). A reflection-cube mip-tail fusion reduced seven dispatches to two and preserved all tested reflection and image bytes. Twenty-eight interleaved runs did not establish a repeatable CPU or GPU benefit, so it also remains archived; the original cube mip chain stays active. The investigation added the benchmark-only thread CPU timer above. See [the cube-mip experiment and retained diagnostics](../docs/optimization-report-2026-10-23-cube-experiment.json). Future optimizations must be measured and checked against image output before adoption.

An immutable binding-list experiment passed twenty exact GPU comparisons, including repeated viewport resizes, but sixteen interleaved runs did not establish a repeatable reduction in mean CPU encoding time. Default improved by 2.1%; stable-time increased by 0.46%, and GPU times were effectively unchanged. The candidate was removed and all accepted production source hashes restored. Its snapshots and resize checks remain under `macos/Tests/Experiments/ResourcePlans/`. See [the binding-list experiment and restoration evidence](../docs/optimization-report-2026-10-23-resource-plans.json).

A subsequent batched-setter experiment also passed twenty exact comparisons and Metal validation through repeated resizes. Twenty-four interleaved runs included a separately built accepted executable to control fallback-wrapper overhead. Mean CPU encoding improved by 1.95% in the default comparison but worsened by 3.34% after the clock transition; GPU time remained effectively unchanged. It was rejected and production restored. See [the batched binding experiment](../docs/optimization-report-2026-10-23-batched-bindings.json).

Three ocean diagnostic-path specializations were tested. Removing the later diagnostic block changed a few HDR values; removing only the early diagnostic return preserved every compared byte across twenty-four scenes and diagnostic modes, but eight interleaved runs showed no useful GPU gain. All candidates were removed and accepted shader hashes restored. See [the diagnostic shader experiment](../docs/optimization-report-2026-10-23-ocean-debug.json).

Two wave-mip scheduling candidates preserved all compared bytes across fourteen cases each. Interleaving the three independent mip chains reduced collective barriers from nine to three without increasing the 2,016-byte threadgroup allocation. A SIMD-shuffle version used one barrier and 1,536 bytes. Twenty-four windowless benchmark runs did not establish a useful frame-time gain; the SIMD version worsened median GPU time by 1.85%. Both were removed and the accepted headless renderer restored. See [the wave mip scheduling experiments](../docs/optimization-report-2026-10-23-wave-mip-scheduling.json).

A six-layout FFT buffer study preserved normalized float32 rows and assembled half-float textures across row-major, column-major, and 4/8/16/32-square tiles. The initial compute-only sweep favored tile16, but sixteen interleaved full-frame runs across column-major and tile16 did not establish a useful GPU improvement. Both candidates matched all twelve rendered comparison states. The accepted fused renderer and all its source hashes were restored; the self-contained component benchmark and candidate snapshots remain under `macos/Tests/Experiments/FFTLayout/`. See [the FFT layout measurements and restoration checks](../docs/optimization-report-2026-10-23-fft-layout.json).

A refreshed fragment-shader investigation tested cascade-loop unrolling, zero-weight foam sample pruning, and zero-mask foam lighting. Variants either changed HDR/display values or failed to establish a useful GPU gain. The accepted evolution-fusion renderer was restored with matching source hashes, Metal validation, and nine fresh exact image comparisons. See [the profile and fragment experiment results](../docs/optimization-report-2026-10-23-fragment-experiments.json).

## Browser reference

The files `index.html`, `js/`, `ocean.html`, and `ocean.min.html` retain the WebGPU renderer for comparison. They are not loaded by the macOS app.

```sh
npm install
npm start       # http://localhost:8080/
npm run build   # rebuild the two HTML bundles after editing js/
```

A browser with WebGPU support is required. The two HTML bundles can also be opened directly from disk. The browser reference retains its development free camera and settings panel; use `?fixed=1&ui=0` for a fixed view. Those browser-only controls do not apply to the native app.

## Shader migration and source ownership

The original WGSL equations were migrated with Naga into the checked-in `macos/Shaders/*.metal` files. Those files are now the **native app's shader sources** and can be edited directly. No translation happens when building or running the app.

Optional migration tools are retained under `tools/` for provenance and reproducing the initial port. They require Node.js and Rust. The exporter writes the initial port to `macos/build/migrated-shaders/` for comparison, preserving the optimized native shader sources. It is not part of the normal build workflow:

```sh
cargo build --release --manifest-path tools/wgsl-to-metal/Cargo.toml
node tools/export-metal.mjs
```

The exporter includes the native projected-grid vertex shader and camera-aware foam work rejection. Shader binding numbers are explicit and match the resources bound in `OceanRenderer.swift`.

## Daylight and remote night sky

The preview automatically uses approximate IP location with no location-permission prompt. Daily sunrise/sunset and orbital samples are cached on disk; UTC drives continuous sun and Moon motion. The fixed west-facing view remains in place. Night reveals a NASA/Gaia-derived Milky Way sky, varied sharp stars, cloud silhouettes, lunar phases and ocean reflections. The Daylight menu shows local timings. See [behavior, cost controls and tests](../docs/day-night-cycle.md); run `npm run macos:daylight:test` for the windowless regression gate.

## Volumetric clouds

The native preview now ray-marches a 1.25 km thick spherical cloud layer with three-dimensional cellular/value-noise structure, altitude shaping, fine erosion, sunlight extinction and interior shadows. Thin, broken high wisps remain inexpensive. The sky, ocean reflection cube and direct-sun visibility share one density model and one bounded, double-precision advection clock. This replaces the old flat low-cloud layer; the retained WebGPU reference is unchanged.

The immutable 64³ RGBA8 shape texture uses 1 MiB. The visible sky cache uses half the internal dimensions and refreshes at most 8 Hz. The marcher takes 48 steps, or 64 near the horizon, skips empty samples, stops when opaque, and drops erosion detail below its pixel footprint. Four expanding samples approximate sunlight extinction; multiple scattering and aerial perspective remain approximations. No per-frame noise volume generation or new simulation loop is added.

Run `npm run macos:clouds:test` for 14 windowless scene checks, exact clear-sky bypass, cloud/reflection/sun readbacks and continuity across the 600 s wave phase boundary. `volumetricClouds=0` retains the previous cloud equations for comparisons (at the new cache resolution). Historical saved captures from the flat-cloud renderer are not expected to match the changed appearance. See [the cloud implementation and measurements](../docs/volumetric-clouds.md).

## Known limitations

- The scene is open ocean only; no shoreline, surf, or objects in the water.
- Low clouds use a bounded volumetric march; high cirrus remain a thin layer. Multiple scattering is approximated, and distant cloud detail is reduced to keep GPU cost bounded.
- The preview trades full Retina sharpness for a bounded GPU workload.
- The viewpoint and horizon composition are fixed; the projected mesh and foam rejection assume that camera.
- Shader compilation occurs at startup; a future distribution build can precompile Metal libraries.
- Desktop wallpaper integration is not implemented yet. Local weather synchronization, severe-storm rendering and gradual transitions are implemented.
- IP location is approximate; lunar positions use a lightweight visual model. Resolved star distribution is procedural; the Milky Way uses a credited NASA/Gaia-derived radiance asset.

## Repository layout

| Path | Contents |
|---|---|
| `macos/main.swift` | Native window, MetalKit viewport, app lifecycle, and diagnostics launch options |
| `macos/ViewportLayout.swift` | Aspect-preserving pixel budget and proportional mesh density |
| `macos/ViewportMesh.swift` | Projected-grid topology with 16-bit indices and a 32-bit fallback |
| `macos/CelestialCycle.swift` | Offline daily solar timings, cached sun/Moon samples and sidereal sky rotation |
| `macos/ObserverLocationProvider.swift` | Infrequent IP geolocation, persistent cache and offline/backoff policy |
| `macos/StarField.swift` | Immutable procedural stellar catalogue and filtered reflection atlas |
| `macos/GalaxyAtlas.swift` | One-time native packed-HDR galaxy upload and mip preparation |
| `macos/Assets/Galaxy/` | Local NASA/Gaia-derived radiance, metadata and credits |
| `macos/AnimationClock.swift` | Double-precision animation clock, periodic texture offsets, and fractional/integer cloud-noise origins |
| `macos/MipmapRounding.swift` | Startup GPU probe of native half-float texture-store rounding, with a fallback to the original mip chain |
| `macos/GPUProfiler.swift` | Optional GPU stage counters; disabled during normal rendering |
| `macos/Tests/`, `macos/test.sh` | HDR equivalence checks, GPU validation, layout tests, and benchmarks |
| `macos/OceanRenderer.swift` | Metal resource allocation, projected-grid indices, compute/render passes, timing, and GPU verification |
| `macos/Shaders/` | Native Metal simulation, atmosphere, clouds, ocean, and post-processing shaders |
| `macos/build.sh` | Optimized Swift build and local app bundle packaging |
| `macos/Info.plist` | App identity and minimum system version |
| `tools/` | Optional one-time WGSL-to-Metal migration tooling |
| `index.html`, `js/`, `ocean*.html` | Original WebGPU reference implementation |
| `server.mjs`, `build.mjs` | Browser reference development and bundling |
| `docs/` | Reference screenshots |

## Origins

The original WebGPU renderer was built with Claude Code (Opus 5.5), including the ocean simulation and sky models. This project extends it into a fixed-view macOS wallpaper and migrates its rendering pipeline to native Metal.

## License

MIT. See [LICENSE](../LICENSE).

### Storm rendering review

Rain now occupies the 3D scene and is occluded by waves. Cloud banks grow vertically and converge before heavy precipitation develops. [Accelerated buildup](../docs/storm-formation.mp4) · [Normal-speed rainfall](../docs/storm-rain-motion.mp4) · [Implementation and measurements](../docs/storm-rework-report-2026-10-30.json). Run `npm run macos:storm:review` to reproduce the native recordings and depth diagnostics.

### Cinematic night visibility

Midnight lighting now reveals wave faces, foam, clouds and rain with cool sky fill and moonlit highlights while preserving deep shadows and the starry sky. The real day/night cycle still sets celestial positions. [Lighting design and validation](../docs/cinematic-night-lighting.md).
