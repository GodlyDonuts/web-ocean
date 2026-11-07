# A visible night arc with real lunar phases

The default Moon crosses the fixed camera frame between local sunset and the following sunrise. It rises at the left sea horizon, reaches its highest point halfway through the night, and sets at the right horizon at sunrise. By day it returns below the horizon. Its displayed position is a cinematic composition, rather than the Moon's geographic position. The Sun and stars retain their astronomical positions.

The arc has the familiar shape of a solar crossing, fitted inside the camera's field of view. It is centered on the fixed view regardless of geographic heading; its horizontal extent adapts to aspect ratio and its maximum elevation is 18°. The camera stays fixed. This implements the requested visible-frame interpretation, rather than repeating a full geographic solar track that spends much of the night off-camera.

## Phases and lighting

The underlying Sun/Moon ephemeris is retained to calculate the date's illuminated fraction and bright-limb orientation. New, waxing, quarter, full and waning phases continue through the real lunar cycle. The existing low-precision visual model is approximate, not a navigation-grade almanac.

Moving a Moon mesh while shading it with the real Sun direction would produce the wrong phase. `WallpaperMoon.phaseLight` transfers the real phase geometry into the displayed disk's coordinate system. The curved terminator changes shape; phase is not merely a whole-disk opacity fade. The existing maria texture remains attached to the disk.

Moonlight, atmospheric glow, cloud lighting, stellar washout and water glints all use the same displayed position. Their strength still depends on illuminated fraction, night factor, horizon visibility and cloud transmission. A new Moon stays nearly dark; the system does not substitute a bright full Moon just to create a reflection.

## Caching and lifecycle

The night interval uses cached sunset and the following sunrise, including across local midnight and DST. The first nighttime request may prepare one adjacent solar-day record. Normal frames perform a small amount of interpolation/vector math; they do not recalculate ephemerides or access the network/disk. Existing eight-record solar storage and IP location policy remain intact. At polar locations without a complete rise/set pair, a continuous 24-hour fallback arc centers its visible half on local solar midnight.

Only the existing frame uniform buffer grows by 16 bytes for the independent disk-light direction. There are no new textures, render passes or timers. The reference `moonPath=astronomical` query retains geographic Moon positioning for developer comparisons; normal launches use the visible arc.

On the local M1, 10,000 cached arc updates averaged less than one microsecond each with no additional astronomy calculations/writes. A short unprofiled 1280×800/30 FPS resource pair measured baseline → updated mean GPU times of 7.87 → 8.11 ms (daylight), 7.86 → 8.15 ms (night) and 10.60 → 11.06 ms (storm). These are individual short runs with intentionally different nighttime lighting directions, not an isolated speedup/overhead estimate. Metal allocation totals remained 76.44 MiB clear / 82.44 MiB storm; whole-system energy and WindowServer are excluded.

## Verification

`zsh macos/test-unit.sh` includes `WallpaperMoonTests`. It samples an entire night in portrait, standard and ultrawide aspects, checks midnight/DST continuity, exact phase fraction and bright-limb preservation after repositioning, cache reuse across 10,000 updates, and finite polar fallback. Calendar fixtures use nearby local nights around the April/May 2024 phases in [NASA's phase table](https://eclipse.gsfc.nasa.gov/phase/phase2001gmt.html).

After building and running those CPU tests:

```sh
python3 macos/Tests/verify_wallpaper_moon.py
```

Actual Metal readbacks check near-new, waxing quarter, full and waning quarter disks, including opposite quarter-moon bright sides. Two accelerated captures advance from one initial UTC and fixed heading to verify visible motion over 30 minutes. The maintained current, daylight and broader suites include this test. Historical astronomical motion remains separately checked with `moonPath=astronomical`.

[Native phase/arc captures](wallpaper-moon-review.png) · [Dated validation and resources](wallpaper-moon-report-2026-11-06.json). Automated captures use fixed public coordinates, zero application windows, no provider calls and no user-cache writes.
