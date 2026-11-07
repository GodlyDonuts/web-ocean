# Offshore sea-state audit

A remote ocean is not necessarily a rough ocean. Wind speed, wind duration and fetch determine locally generated waves; swell can arrive from storms thousands of miles away and remain when local winds are light. See [NOAA's wind-wave and swell explanation](https://www.noaa.gov/jetstream/ocean/waves).

## Findings and changes

The renderer uses metre-scale deep-water gravity/capillary waves across six spectral cascades. Its JONSWAP wind sea uses an idealized 90 km fetch. A separate directional swell term supplies offshore rollers. The fixed camera is 2.4 m above mean sea level; a metre-scale swell can look gentle when its wavelength is long. These are coherent scene units, not an arbitrary visual wave-height multiplier.

The audit found that the old swell input was `1.8 + 8 * weather.severity`, where severity includes rain. Heavy rain with weak wind could therefore create an enormous sea without the wind history or remote storm necessary to explain it. The old fixed 120 m peak wavelength also made the larger swell unnecessarily steep. Foam thresholds were coupled to the same rain-derived severity.

The correction:

- Retains an independent, idealized 1.8 m nominal swell-height input and changes its peak period from about 8.77 s to 11 s (about 189 m deep-water wavelength). The fixed direction/spreading remain; this is not a remotely observed swell forecast.
- Lets the existing wind spectrum supply additional wave energy. Startup and subsequent targets now retain the same JONSWAP peak-shape parameter and the same background swell. Wind direction changes retain the existing phase-preserving 90-second response.
- Uses wind severity for whitecap thresholds; rain/clouds/thunder can still change atmospheric appearance without manufacturing large waves or foam.
- Regenerates target wave spectra only when wind speed/direction change. Rain/cloud-only updates retain the current sea and avoid an unnecessary spectrum initialization.

No new FFTs, passes, buffers, textures, timers, network requests or moving-camera behavior were added. The recent daylight treatment and lock/wake drawable fixes remain in use.

## Actual GPU measurements

The height check reads six 256×256 displacement layers and computes `4 * sqrt(sum(cascade elevation variances))`. This is a spectral height proxy for this finite simulation, consistent with the variance-based approach described in [NDBC wave measurement procedures](https://www.ndbc.noaa.gov/wavemeas.pdf). It is not the largest individual crest-to-trough height, a wave-buoy time record or a forecast for the user's location. Actual sea-surface geometry is measured, rather than assuming the `swellHs` input equals the rendered height exactly.

At fixed wave time 30 s, direction and deterministic seed:

| Local wind | New height proxy |
|---|---:|
| Light wind, 2.75 m/s | 1.52 m |
| Same wind with heavy rain/thunder | 1.52 m; displacement bytes identical |
| Breeze, 7 m/s | 1.97 m |
| Strong wind, 15 m/s | 3.03 m |
| Gale, 30 m/s | 5.27 m |
| Extreme wind, 45 m/s | 7.05 m |

The light-wind proxy stays about 1.50–1.56 m at wave times 10, 30, 60 and 120 s. Removing only the swell lowers it to 0.63 m, confirming the larger rollers persist independently of weak local wind. Before correction, a diagnostic equivalent of the old rain-only swell mapping measured about 6.99 m; the old extreme-wind/swell combination measured about 11.15 m. These fixed-seed results are model measurements, not universal weather-to-wave conversion values.

## Verification and continuing work

Run `python3 macos/Tests/verify_sea_state.py` after building. The maintained gate includes it. Ten actual GPU cases check bounded wave fields at multiple times, independent background swell, monotonic wind-driven growth and exact dry/wet displacement invariance. The `weatherValues` headless fixture takes validated `rain,cloud,wind,direction,thunder,mist` values; production weather continues to use its normal cached provider. `swellHs` and bounded `swellPeriod` are diagnostic query inputs, not new menu controls.

The severe-weather regression now expects a wind-generated extreme sea rather than requiring rain-inflated swell. Its hurricane lower-height assertion was changed from 8 m to a bounded 5–14 m range with substantial growth over fair weather. Existing phase-onset, growth/settling and long-clock checks remain.

The night-water fixture still requires overtaking geometry and lit, structured foam. The previous requirement for 100 pixels above 50% foam coverage depended on the old inflated swell. The updated fixture requires over 1,000 pixels above 25% coverage and a peak above 40%, accepting thinner foam while still rejecting an empty or flat mask. It retains the waterline black-pixel and night-lighting checks.

[The dated report](sea-state-report-2026-11-07.json) records final checks and installation. Raw logs and fields are under ignored `macos/build/sea-state-audit/` and `macos/build/sea-state/`.

Remaining simplifications: the user's weather may be inland; gusts contribute to the existing visual wind estimate; fetch is fixed; the 90-second response compresses real wave-growth times; remote swell direction/energy are not fetched; and FFT choppiness/foam do not constitute a complete breaking-wave fluid simulation. A true marine match would require an explicitly chosen offshore location and wave-spectrum data, beyond IP weather alone.
