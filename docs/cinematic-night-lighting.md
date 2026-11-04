# Cinematic midnight lighting

Night is lit for a wallpaper rather than strict physical darkness. The Sun/Moon positions, phase, sunset timings and rotating star field still follow the existing local-time model. Lighting continuously blends through its existing twilight/night factor.

The scene uses three complementary sources:

- A deep indigo horizon and softly brighter overhead hemisphere separate cloud silhouettes and provide reflection detail. A broad off-frame sky key adds direction without an artificial visible celestial disk or city-light glow.
- The real Moon supplies a stronger photographic key and glitter path when it is above the horizon, with its actual direction and phase retained. This is an artistic light intensity, not measured lunar irradiance.
- A low-angle cool fill responds to the water normals, revealing moving faces and crests while keeping troughs dark. It remains available during a moonless or overcast night.

Clouds, fog and reflected light share the sky illumination. The 3D rain uses that same environment with a restrained nighttime scattering floor, so rain is legible against storm clouds and waves. The existing exposure and tone mapper remain unchanged. There is no screen-space brightness floor, black-level lift or new glow overlay.

All changes run inside existing lighting, sky and ocean passes. There are no additional textures, simulation loops or render passes. Daytime and daytime-storm HDR/display captures match the saved pre-change build exactly in matched production settings.

## Verification

`macos/Tests/verify_cinematic_night.py --before` captures the saved `macos/build/night-cinema/Before.app` baseline; running the script without that flag captures the current app and verifies visibility, cool color, shadow/crest contrast, visible rain and daytime parity. It uses Python NumPy/Pillow for development readbacks, not at app runtime. Fixtures cover moonlit, moonless, starry, stormy and moonless-storm nights, plus daytime and a daytime storm. GPU tests never create a window, contact a service or update the user's location/solar cache.

The [night lighting report](cinematic-night-lighting-report-2026-10-30.json) includes matched measurements, images and frame timings. The normalized display-RGB luma statistics are readability proxies, not physical luminance or energy measurements. Visual review checks that the scene still reads as midnight and that the stars and wave shapes retain contrast.

## Recorded results

The moonless-storm ocean median display-luma proxy rose from **0.018 to 0.142**; near-black ocean samples fell from **73% to 0%** in the chosen central-water crop. Wave contrast remains: its 10th–90th percentile spans **0.087–0.179**. More than **32,000** nighttime rain pixels produce a visible difference against the matched no-drop frame. Moonlit, moonless and stormy visual fixtures were reviewed as native rendered imagery.

Matched production daytime and daytime-storm HDR/display files are byte-identical to the saved prior build. The moonless hurricane passed Metal API/shader validation, all 13 daylight/night fixtures passed, and actual rendered Sun/Moon motion checks still pass.

Eight sequential unprofiled M1 runs measured clear-night mean GPU time **8.94 → 8.81 ms**, and storm-night mean **11.09 → 11.45 ms**, with storm P95 **25.37 → 24.49 ms**. Short-run variation is present; these figures establish the measured frame budget rather than an isolated speedup. The internal target remains 1280×800 at 30 fps, with 60 warmup frames excluded from each 180-frame run.

[Midnight preview](cinematic-midnight-preview.png) · [Moonless storm](cinematic-midnight-storm.png) · [Before/after comparison](cinematic-midnight-comparison.png).

## Camera-visible sky refinement

Following visual feedback, the camera-visible sky now uses restrained neutral airglow and a Moon-local halo instead of displaying the broad blue lighting hemisphere. The cinematic illumination still lights the ocean and cloud volumes. The unresolved galactic background is softened and subdued, while full-resolution foreground stars stay sharp. Visible nighttime clouds receive a modest neutral-color adjustment. Matched moonlit, moonless, storm and daytime captures retain byte-identical ocean HDR pixels; daytime HDR is unchanged. [Current preview](night-sky-natural-preview.png) · [Comparison](night-sky-natural-comparison.png) · [Evidence](night-sky-natural-report-2026-10-30.json).

## Storm waterline and foam correction

The later [waterline correction](night-water-fix.md) extends near-camera geometry, handles submerged views and shares the wave fill with foam. It corrects black coverage gaps during overtaking waves and removes foam from their undersides. Those geometry and shading corrections also affect daytime storm crests; the earlier byte-identical daytime comparison above describes the initial lighting-only revision.
