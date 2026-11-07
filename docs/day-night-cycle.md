# Local daylight and the remote night sky

The [Daylight menu](daylight-controls.md) now supports holding Sunrise, Midday, Golden Hour, Sunset, Midnight or a custom local clock time. Follow Local Time restores the normal live cycle. Water, cloud motion and weather remain animated in either mode.

Normal preview launches now follow real UTC and approximate location obtained from the public IP address. There is no GPS, macOS location prompt, location-entry dialog, geocoder or API key. [Local weather](dynamic-weather.md) now reuses these coordinates for a separate cached current-conditions request. A small asynchronous HTTPS request to [ipwho.is](https://ipwhois.io/documentation) asks only for success, latitude, longitude and IANA time zone. It normally runs once per 24 hours. Rounded coordinates, time zone and timestamps stay in `~/Library/Application Support/OceanWallpaper/ip-location.json`; the public IP and raw response are not saved.

The provider keeps using saved coordinates while offline and backs failed requests off for 15 minutes, including across app restarts. A local expiry check shares active rendering about once a minute; no new background timer wakes a hidden wallpaper. The Daylight menu shows today's sunrise/sunset and offers **Refresh Approximate Location**. On first launch without connectivity or any saved location, the preview retains fixed lighting until a lookup succeeds. VPNs/relays can change the approximate area; this follows the requested IP-based policy.

## Rare calculations, continuous movement

`CelestialCycle.swift` calculates sunrise, sunset, civil dawn/dusk, solar noon and hourly equatorial sun/moon samples for the local date. It stores up to eight recent records in `celestial-days.json`, keyed by date range, coordinates, time zone and model version. Restarting on the same day reuses the record; a new day, location or time zone generates a new one. Corrupt/stale data is rebuilt. No JSON reads/writes or full ephemeris calculations occur during ordinary cached frames.

Sunrise/sunset use the standard -0.833° geometric solar altitude and a bracketed crossing search. Solar coordinates follow the [US Naval Observatory's approximate almanac equations](https://aa.usno.navy.mil/faq/sun_approx); event conventions are checked against [NOAA's equations](https://gml.noaa.gov/grad/solcalc/solareqns.PDF). Solar-disk refraction is handled separately from the geometric atmosphere direction. Below the visible horizon, its correction tapers smoothly between −2° and −1° instead of snapping off; visible sunrise/sunset positions are unchanged. These are standard-atmosphere predictions for an unobstructed sea horizon, with approximate IP coordinates.

The Moon uses a small mean-element model in the family documented by [SunCalc](https://github.com/mourner/suncalc-go/blob/master/suncalc.go), observer parallax, approximate refraction and its own varying phase/distance. It is a low-precision visual ephemeris, not a high-precision lunar almanac. The current [wallpaper presentation](wallpaper-moon.md) uses this model for real phases while placing both bodies on one centered camera arc: the Sun during daylight and the Moon during the night. A separate phase-light vector preserves the curved terminator after repositioning. Ocean/cloud lighting follows that displayed Moon.

The underlying ephemeris interpolates hourly equatorial samples and applies Earth rotation for real lunar phase and night/twilight state. Displayed Sun/Moon positions deliberately follow the shared centered arc between cached sunrise/sunset boundaries. Live astronomy uses UTC independently of the bounded wave clock, so it remains current after sleep or hidden periods. Polar day/night, daylight-saving 23/25-hour days, longitude wrap, clock changes and missing location are handled explicitly.

The camera remains fixed, facing geographic west (270°) by default. Both displayed bodies share a centered path in that view; the camera does not chase either one. Developer fixtures can choose `heading`, `utc`, `timeZone`, `latitude`, `longitude`, `cycleRate` and the historical `celestialPath=astronomical`. These are test inputs, not extra questions in the product. `dayNight=0`, or an explicit fixed `sunElev` on a normal launch, retains fixed lighting. Headless verification defaults to fixed lighting unless `dayNight=1` is explicitly requested, and never performs an IP lookup.

## Cinematic dark-sky ocean

The night sky is art-directed as a remote ocean with no city-light pollution: a dense field of procedural stars, blue-white/gold color variation, a NASA/Gaia-derived Milky Way, detailed dust lanes, moonlight and dark cloud silhouettes. Its intensity is a photographic/artistic treatment, rather than a simulation of naked-eye brightness.

A deterministic catalogue of 12,000 directions/fluxes is generated once, with a broad brightness distribution and restrained stellar colors. Fine stars are small analytic round sprites drawn in the existing HDR render pass, with the existing sky-only depth test, and masked by cached cloud transmission. They stay sharper than the lower-resolution cloud cache. A filtered 1024×512 R16F atlas supplies unresolved starlight to the reflection cube. The atlas plus all mips use about 1.33 MiB, and the catalogue about 0.18 MiB. There is no recurring catalogue generation or additional render loop.

The Milky Way uses [NASA SVS Deep Star Maps 2020](https://svs.gsfc.nasa.gov/4851/), derived from stellar catalogue observations, with the bright Hipparcos/Tycho foreground omitted. It replaces the cloud-noise galaxy. A local 2048×1024 linear HDR asset is packed directly for Metal R11G11B10 sampling; it needs about 10.67 MiB including mips (slightly more in device allocation). Runtime uses one filtered lookup instead of several 3D noise evaluations. The observed background retains warm/cool structure and fine dust detail, while the resolved foreground stars remain procedural artwork. [Asset credits and provenance](../macos/Assets/Galaxy/CREDITS.md) are also included in the app bundle.

Galaxy radiance remains in the half-resolution sky cache at at most 8 Hz. The celestial sphere rotates with UTC, location and the fixed scene heading; clouds occlude it, horizon extinction and moon glare reduce visibility, and reflections use footprint filtering. There is no new render loop, network image fetch, per-frame upload or recurring image synthesis. The prior procedural version's evidence is retained in the earlier report; the current [cinematic-sky checks and comparison](cinematic-night-report-2026-10-30.json) cover this revision.

## Verification

`npm run macos:daylight:test` builds the app and runs offline CPU/IP-policy tests plus 13 synthetic GPU scenes with Metal API/shader validation. Automated tests use no windows, location permissions, IP requests or user-cache writes. Fixtures cover sunrise, morning, noon, sunset, twilight, moonlit/starry/dark nights, polar cases, portrait and unavailable location. The suite also samples 1,441 positions across a full day and measures actual Sun/Moon disk movement in HDR captures taken 30 simulated minutes apart with each camera fixed. Each later capture advances 188 frames from the same starting UTC as its early capture, exercising live uniforms and sky-cache refreshes. Additional checks cover disk-cache hits/recovery, DST, lunar phases, observer/heading rotations, sidereal motion, native packed-HDR decoding and reflection-atlas energy. Cached-frame accuracy tests compare interpolation against the same underlying model, not a higher-precision external ephemeris.

A local release test on this M1 measured roughly 7–10 ms to calculate/save a day and about 0.28–0.35 microseconds per cached position query. Ten thousand queries produced one daily calculation and one cache write. These are component CPU measurements, not total rendering/energy measurements.

`python3 macos/Tests/benchmark_day_night.py` runs sequential unprofiled day/night frame-budget checks with warmup excluded. See [the recorded evidence](day-night-report-2026-10-30.json) for the final results. Whole-system energy, display composition and WindowServer are not measured by these headless tests.

Measured unprofiled command-buffer times in the final four-run budget check:

| Scene | Mean GPU frame time | 95th percentile |
|---|---:|---:|
| Day | 7.16 ms | 9.64 ms |
| Starry night | 7.37 ms | 9.45 ms |

These fit the 33.3 ms frame budget in this short M1 test. The two scenes have different lighting/cloud demand, so the difference is not an isolated measurement of star-rendering overhead.

## Cinematic-sky revision measurements

Eight matched alternating night runs measured median run-mean GPU time of **7.74 → 7.24 ms** on this M1 (about 6.4% lower); median run 95th-percentile time fell **10.26 → 9.65 ms**. Four daytime runs were essentially unchanged (**7.39 → 7.36 ms**). All runs used the same 1280×800 internal target, 30 fps cadence, synthetic location/time and 180-frame duration, excluding 60 warmup frames. The appearance deliberately changes, so this is a quality/performance revision rather than a bit-identical kernel optimization.

The new background adds about 6.5 MiB net device-allocated sky resources after reducing the reflection-star atlas by four times. A 1K-versus-2K comparison measured HDR relative L2 difference of 0.00000104. The packed background's offline encoding error is 0.43% relative L2 versus the linear source. Native GPU samples match independent bit decoding, and integrated starlight differs by 0.059% between the two reflection-atlas sizes. These checks do not measure battery life or WindowServer energy.

## Continuous celestial-motion verification

The [motion report](celestial-motion-report-2026-10-30.json) records full-day continuity, actual rendered disk motion and an accelerated 24-hour render-loop rollover check. That report describes the historical astronomical mode, where both bodies follow independent paths; stars rotate with sidereal time. Current visible-arc evidence is in the [Moon presentation guide](wallpaper-moon.md). A below-horizon refraction discontinuity found by this test was corrected. The rendered Sun moved about 105 pixels and the Moon about 85 pixels over the tested 30-minute intervals, matching their projected paths within 0.2 pixels of displacement. Tests use synthetic coordinates and never open a window or update the user’s location/day cache.

For offscreen diagnostics, `verifyFrame` selects the capture frame (default 8, bounded to 8–3600). Ordinary launches keep real UTC and have no accelerated clock. Accelerated test timings are not performance measurements.

## Cinematic midnight visibility

The night scene now uses [cinematic lighting](cinematic-night-lighting.md): soft indigo sky fill, a stronger real-Moon key and a grazing water fill reveal clouds, rain and wave shapes without lifting the display black level. The artistic illumination is separate from astronomical position/timing accuracy. Daytime output remains unchanged in matched native captures.

## Stars and cloud integration

Night stars use tighter, softer-colored points. Both the visible galaxy and reflected starlight lose contrast through thin cloud veils and vanish behind thick clouds, using the same transmission curve. The Milky Way also fades smoothly with overall cloud cover so its dust lanes do not compete with foreground cloud banks. This is an artistic contrast adjustment, rather than a physical exposure model. Clear nights retain the detailed galactic band.

This adjustment adds no render passes, textures, catalogue entries or cloud-marching steps. The existing moon path, weather timing and cinematic water illumination are retained. See [the paired native captures and validation](night-sky-integration-report-2026-10-30.json).
