# Native volumetric clouds

The current [cloud family system](cloud-variety.md) extends this foundation with low decks, middle patches/sheets and high wisps/cells/veils. Measurements below describe the earlier volumetric revision; the new guide records current forms and validation.

The low clouds now occupy a spherical layer from 1.5 to 2.75 km altitude in fair weather, growing toward a 1 to 7.25 km storm layer rather than a single textured shell. The fixed camera looks through three-dimensional density, with cellular/value-noise billows, altitude-dependent shaping, finer erosion and large-scale coverage variation. Four expanding sunlight samples provide interior shadows. Beer–Lambert extinction accumulates premultiplied radiance front-to-back; an inexpensive multiple-scattering term and distance haze soften the transition into the atmosphere. Broken high cirrus remain a thin, much less opaque layer.

`VOLUMETRIC_CLOUDS.metalinc` is inserted into the three native sky libraries at startup. The visible sky, all six reflection faces and seven direct-sun visibility rays use the same density/coverage/advection model. The sun's optical transmission is separate from the aerial-perspective opacity used when compositing cloud radiance, so distant haze does not accidentally make thick clouds transparent to the sun. The sun-visibility basis also handles a sun directly overhead.

## Cost controls

- One immutable 64³ RGBA8 noise texture: 1,048,576 bytes, generated once on the CPU. Hardware trilinear samples replace repeated procedural hash evaluation inside the march.
- The sky cache is half the internal render width/height and updates at most 8 Hz. Water geometry and scene render resolution are unchanged.
- Distance-adaptive view steps (40 m plus 0.3% of travel distance), capped at 448 iterations and 100 km, with zero-density skips and opacity early termination. Storm shadow residuals use a tighter cutoff. Distant sub-cloud rain uses 16 bounded samples.
- Fine erosion is omitted when smaller than the estimated pixel footprint. The shadow march uses the cheaper density variant.
- Reflection updates retain the existing one-face-at-a-time cadence. Cloud state is shared, though sky/cube cache timestamps can differ.
- No new per-frame simulation, noise-volume update, worker loop or extra presentation window.

Samples start consistently at the condensation boundary and use distance-adaptive quadrature rather than time-varying grain. Erosion is reduced below the sampling footprint and in mature banks to limit marching contours and sparkling rims. This avoids a temporal history/reprojection allocation, at the expense of possible undersampling at very shallow angles. Motion uses double-precision elapsed time reduced separately into periodic texture coordinates, preserving continuity at the wave clock's 600 s boundary. Cloud banks travel with the configured ocean wind; high cirrus travel faster with anisotropic filaments. Slow independent erosion phases deform the billows even with zero wind. Integer octave ratios preserve texture-phase wrap continuity. Accelerated UTC previews apply the same timeline multiplier to clouds and celestial bodies, while ordinary launches use normal speed. Legacy/unwrapped development clock modes deliberately retain their old failure behavior for regression comparisons.

## Validation and measurements

`python3 macos/Tests/verify_volumetric_clouds.py` captures sunset, daylight, dense coverage, clear, high-only, low-only, night, overhead sun, portrait, ultrawide, month uptime and both sides of the old clock boundary. It checks real GPU output, finite sky/environment/sun readbacks, valid sun transmission, exact clear-sky reference equality and small clock-boundary changes. Automated runs have zero windows and prohibited activation. The full scene captures are visual fixtures, not a physical reference solution.

Initial 14-scene validation also ran with both Metal API and shader validation enabled. The final host change only makes legacy/unwrapped development modes reproduce their original clock behavior; production continuous-clock rendering is unchanged.

An unprofiled, sequential ABBA comparison on this Apple M1 used 180 frames per run, discarded the first 60, and compared the saved pre-change app with volumetric rendering at the default 1280×800 internal resolution. Median run summaries:

| Metric | Previous layered clouds | Volumetric clouds |
|---|---:|---:|
| Mean GPU frame time | 7.09 ms | 7.75 ms |
| Median GPU frame time | 6.60 ms | 7.48 ms |
| 95th percentile GPU frame time | 10.02 ms | 11.23 ms |

This is roughly 0.66 ms more mean GPU time in this short comparison. Both fit within the 33.3 ms budget at the default 30 fps. The comparison includes the intentional cache-resolution and cloud-appearance changes; it does not isolate just the ray marcher. Individual runs varied, and these are command-buffer timings, not whole-system energy, GPU occupancy or WindowServer measurements. Initialization/noise generation and shader compilation are outside the measured steady-state window. Dense weather and other display/GPU configurations can cost more.

To repeat against a saved prior app:

```sh
python3 macos/Tests/benchmark_volumetric_clouds.py --baseline-app /absolute/path/to/PreviousOcean.app
```

`volumetricClouds=0` retains the old low/high cloud equations at the **new** sky cache size for development comparisons. The WebGPU reference renderer is unchanged. See [the recorded validation and timing evidence](volumetric-clouds-report-2026-10-30.json).

## Remaining limits

Multiple scattering, aerial perspective and short shadow integration are approximations. This is a bounded wallpaper renderer, not a full path-traced atmosphere. The density field is procedural, periodically advected and slowly eroded; full storm fluid physics remain future work. [Local weather synchronization and continuous storm transitions](dynamic-weather.md) are now implemented. Cached clouds can look softer than water, particularly when the output is enlarged. Night illumination is now [art-directed for readability](cinematic-night-lighting.md), with the existing exposure policy retained. Further quality tuning should use animated comparisons, especially at low sun and near the horizon, rather than increasing the sample count without measuring cost.

## Cloud realism and motion revision

The revised density field varies vertically through the layer, separates broad coverage from the rounded cloud tops, and erodes the edges more than the dense cores. Reduced ambient fill at the cloud base strengthens depth; forward-lit boundaries receive a bounded powder-scattering approximation. The view/shadow step limits, immutable 1 MiB noise volume and 8 Hz half-resolution sky cache are retained. The extra motion state is eight bounded phases, with no density simulation or texture uploads.

`python3 macos/Tests/verify_cloud_motion.py` isolates movement with fixed lighting, checks wind advection over 30 seconds, shape evolution with zero wind over 20 minutes, continuity across the old 600-second clock wrap, and exact cached-sky agreement between an accelerated 188-frame run and its equivalent static-time capture. The normal cloud test command includes these checks. See [the current motion and rendering report](cloud-realism-report-2026-10-30.json) for evidence and comparison measurements.

Matched four-run ABBA measurements for this revision on the M1 recorded median run-mean GPU time **7.42 → 7.83 ms**, with median run P95 **10.41 → 11.03 ms**. Both revisions use volumetric clouds and the same internal resolution/cadence. This is approximately 0.41 ms additional mean GPU time; no battery-life claim is made. All 14 cloud scenes and eight motion fixtures passed Metal API/shader validation; all 13 day/night scenes passed separately.
