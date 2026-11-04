# Native architecture

## Host and state

`macos/main.swift` owns AppKit lifecycle, the MetalKit view and menus. `OceanRenderer.swift` currently owns both shared world state and surface resources. The next architectural split is shared ocean/environment state versus per-display presentation.

`CelestialCycle.swift` supplies cached daylight and approximate lunar motion. `ObserverLocationProvider.swift` fetches coarse IP location; `WeatherProvider.swift` fetches current weather. Both use disk caches and retry/offline behavior. `Weather.swift` smooths environmental state. `AnimationClock.swift` distinguishes elapsed time from bounded wave phase and accumulated texture/noise advection. Do not use the ten-minute wave phase as the clock for astronomy or provider validity.

The renderer submits at most one frame at a time using a semaphore. Normal rendering pauses on minimization, occlusion, sleep and inactive session. Viewport dimensions preserve aspect ratio within a bounded internal pixel budget. Resize rebuilds screen-sized targets and mesh indices; most persistent resources are reused.

## Frame and resources

1. Initialize immutable spectrum/noise/foam detail, atmospheric lookup resources and stellar assets. Load and compile the native shaders listed in `Shaders/manifest.json`. Shared `.metalinc` files are expanded by the Swift loader where required.
2. Evolve six periodic wave spectra and perform inverse FFTs. The normal path fuses evolution and row FFT; the column transform produces displacement, derivatives and moments. Fused mip dispatches preserve intermediate half-precision store boundaries; a startup probe selects the texture rounding behavior.
3. Update persistent world-space foam in two 512×512 clipmaps, with advection/injection/decay and bounded camera demand. Weather modifies sea energy continuously while retaining phase identity.
4. Sample surface height at the camera on the GPU, approximately inverting horizontal chop. Retain a tiny waterline state for background scattering, underwater absorption and rain/star visibility.
5. Refresh atmospheric lookup/sun visibility up to 4 Hz, a 128×128 environment cube incrementally up to 10 Hz, and a half-dimension visible-sky cache up to 8 Hz. These caches have different consumers and dependencies.
6. Draw the displaced projected ocean grid into memoryless 4× MSAA color/depth with an integrated HDR resolve. Draw cached sky and full-resolution stars only where ocean depth permits; draw geometric rain with wave-depth occlusion.
7. Run six bloom levels and the display composite with AgX tone mapping and dithering. Store the resolved HDR/display outputs, not transient MSAA/depth attachments.

Volumetric cloud density is shared across the visible sky, reflection cube and sunlight visibility. `VOLUMETRIC_CLOUDS.metalinc` controls the layer structure and bounded adaptive march. The camera-visible night backdrop is deliberately dimmer than the broad cinematic fill used to illuminate the sea. Do not undo that separation while adjusting stellar/cloud contrast.

## Shader map

| Files | Responsibility |
|---|---|
| `SIM_INIT`, `SIM_EVOLVE*`, `FFT_*` | Spectrum creation, phase evolution and Fourier transforms |
| `SIM_MIPS*`, `ARRAY16_MIPS*`, `RGBA8_MIPS`, `CUBE_MIPS` | Typed mip chains and fused variants |
| `FOAM_TEX`, `FOAM_UPDATE*` | Detail generation and persistent foam |
| `WEATHER_SEA` | Phase-preserving transition toward target sea energy |
| `TRANS_LUT`, `MS_LUT`, `SKYVIEW_LUT` | Atmospheric lookup tables |
| `SKY_BG`, `ENV_CUBE`, `SUN_VIS` | Visible sky cache, reflected sky and direct-light visibility |
| `VOLUMETRIC_CLOUDS.metalinc` | Shared cloud density/lighting |
| `CELESTIAL_SKY.metalinc`, `STELLAR_POINTS.metalinc`, `STARS` | Moon, galactic radiance and resolved/unresolved stars |
| `OCEAN` | Projected geometry, surface/foam lighting and absorption |
| `CAMERA_WATER`, `WATER_VIEW.metalinc`, `SKY_CACHED` | Eye waterline and shared sea-volume background |
| `RAIN` | World-space rain streaks with scene depth |
| `LIGHTING` | Shared environment samples used by surface lighting |
| `DISPLACEMENT_BOUNDS*` | Conservative guards for very narrow viewports |
| `BLOOM_*`, `COMPOSITE` | HDR bloom, display mapping and weather effects |

Names refer to `.metal` sources in `macos/Shaders/`; inspect the manifest for actual entry points. Swift and Metal frame layouts/slot indices are a shared ABI: update all relevant consumers together, including stable/reference variants. Resource binding indices are intentionally sparse. Guard data at vertex buffer 13 and camera-water data at fragment buffer 13 belong to separate stages; avoid overwriting either through broad binding helpers.

## Ownership and reference boundaries

Native `.metal` sources are authoritative and hand-edited. The browser `js/wgsl/` tree and optional Rust/Naga migration tools retain the original equations and export path. Re-exporting can overwrite native-only weather, clouds, stars and waterline changes. Review exports as a migration operation, not a routine build step.

The mesh is viewport-focused with sparse guards, including a near patch extending behind the eye. It is not a surrounding dense world. Whole FFT tiles and offscreen sky directions remain necessary because visible waves, reflections and lighting consume them. Do not crop simulation inputs merely because their coefficients or texels are not directly displayed.

Historical `Tests/Experiments/` sources are comparison candidates and rejected trials. Their existence is not evidence that they are production paths. Refer to the corresponding reports before repeating them.
