# One centered Sun/Moon arc with real lunar phases

The Sun and Moon now use **the same path through the middle of the camera**. The Sun travels it from local sunrise to sunset; the Moon repeats it from sunset to the following sunrise. Each starts just left of center at the horizon, reaches the top over the center of the shot, and sets just right of center. The inactive body returns below the horizon. Both positions are cinematic compositions. The camera stays fixed.

The shared trajectory occupies approximately the middle third of the image horizontally and peaks at 18° elevation. Its width adapts to aspect ratio. The underlying astronomy still supplies real local sunrise/sunset, twilight/night transitions, lunar phases and the rotating stars. The earlier Moon-only version kept the Sun geographic; the current implementation deliberately repositions **both** bodies as requested.

## Phases and lighting

The underlying Sun/Moon ephemeris is retained to calculate the date's illuminated fraction and bright-limb orientation. New, waxing, quarter, full and waning phases continue through the real lunar cycle. The existing low-precision visual model is approximate, not a navigation-grade almanac.

Moving a Moon mesh while shading it with the real Sun direction would produce the wrong phase. `WallpaperSky.phaseLight` transfers the real phase geometry into the displayed disk's coordinate system. The curved terminator changes shape; phase is not merely a whole-disk opacity fade. The existing maria texture remains attached to the disk.

Sunlight, moonlight, atmospheric glow, cloud lighting, stellar washout and water glints all use the corresponding displayed position. Their strength still depends on illuminated fraction, night factor, horizon visibility and cloud transmission. A new Moon stays nearly dark; the system does not substitute a bright full Moon just to create a reflection.

## Caching and lifecycle

The night interval uses cached sunset and the following sunrise, including across local midnight and DST. The first nighttime request may prepare one adjacent solar-day record. Normal frames perform a small amount of interpolation/vector math; they do not recalculate ephemerides or access the network/disk. Existing eight-record solar storage and IP location policy remain intact. At polar locations without a complete rise/set pair, a continuous 24-hour fallback arc centers its visible half on local solar midnight.

Only the existing frame uniform buffer grows by 16 bytes for the independent disk-light direction. There are no new textures, render passes or timers. The reference `celestialPath=astronomical` query restores geographic positions for both bodies in developer comparisons; normal launches use the shared centered arc. `moonPath=astronomical` is retained as a Moon-only comparison override.

The cached arc calculation remains a fraction of a microsecond on the local M1. The [Moon-only report](wallpaper-moon-report-2026-11-06.json) preserves earlier measurements. [Current shared-path validation](centered-sky-report-2026-11-06.json) records this revision's matched path, phase and GPU checks.

## Verification

`zsh macos/test-unit.sh` includes `WallpaperMoonTests`. It samples an entire night in portrait, standard and ultrawide aspects, checks midnight/DST continuity, exact phase fraction and bright-limb preservation after repositioning, cache reuse across 10,000 updates, and finite polar fallback. Calendar fixtures use nearby local nights around the April/May 2024 phases in [NASA's phase table](https://eclipse.gsfc.nasa.gov/phase/phase2001gmt.html).

After building and running those CPU tests:

```sh
python3 macos/Tests/verify_wallpaper_moon.py
```

Actual Metal readbacks check near-new, waxing quarter, full and waning quarter disks, including opposite quarter-moon bright sides. Two accelerated captures advance from one initial UTC and fixed heading to verify visible motion over 30 minutes. The maintained current, daylight and broader suites include this test. The same checks now include actual GPU Sun motion and finite midday Sun output. CPU checks require identical positions at matching day/night progress and central framing for both bodies. Historical astronomical motion remains separately checked with `celestialPath=astronomical`.

[Current Sun/Moon captures](centered-sky-review.png) · [Current validation](centered-sky-report-2026-11-06.json). The [Moon-only captures](wallpaper-moon-review.png) and [report](wallpaper-moon-report-2026-11-06.json) describe the prior revision. Automated captures use fixed public coordinates, zero application windows, no provider calls and no user-cache writes.
