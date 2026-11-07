# Choose and hold a daylight time

Open the wave icon in the menu bar, then **Daylight**. The preview window offers the same Daylight menu.

- **Follow Local Time** uses the current time and approximate IP location.
- **Sunrise**, **Midday**, **Golden Hour**, **Sunset**, and **Midnight** hold a lighting preset.
- **Custom Time…** opens a native hour/minute picker. Choose a local time and press **Apply**; **Cancel** keeps the previous setting.

A checkmark identifies the active choice. Custom time also appears beside its menu item. The choice survives quitting/reopening the app. Select **Follow Local Time** to restore automatic daylight immediately.

Holding the lighting does not pause the wallpaper. Waves, cloud motion, rain, weather refreshes and storm transitions keep running. Sun/Moon positions, sky rotation and illumination use the selected time. The real lunar model still supplies the phase for that date/time.

## Time and date behavior

The clock uses the observer's IP-derived time zone, as do sunrise/sunset. Presets use today's cached local events: Midday is solar noon; Golden Hour is 45 minutes before sunset, shortened for very short days. Midnight is local 00:00. Custom time is a local clock time, not an elapsed offset from UTC.

The selected time is held within today's local date. At the next local date the app resolves that time again, so seasonal solar events and lunar phases keep following the date. Changing location/time zone also refreshes the held date. DST gaps choose the next valid local time; repeated clock times choose the first occurrence. Sunrise/sunset-dependent presets are disabled where those events do not occur. If a saved event preset becomes unavailable after moving, lighting follows local time until an event is available or another choice is selected.

## Implementation and verification

`DaylightTime` in `CelestialCycle.swift` resolves the setting. `OceanRenderer` caches the held date until the mode, local date, location or time zone changes. Ordinary held frames do not add calendar/ephemeris calculations, network calls, render passes or timers. The existing animated scene clocks remain independent.

Normal UI selections save one `OceanDaylightTime` value in the app's standard user defaults. Headless fixtures never read/write this preference. Developer fixtures can use `daylightTime=sunset`, `daylightTime=midday`, `daylightTime=goldenHour`, `daylightTime=midnight`, `daylightTime=sunrise`, `daylightTime=automatic`, or `daylightTime=18:30` with the existing deterministic location/UTC query inputs.

`DaylightTimeTests` covers parsing/persisted-value roundtrip, presets, local clock times, DST, daily updates and missing polar events. After a build, `python3 macos/Tests/verify_daylight_time.py` checks six actual Metal fixtures: held sunset before/after simulated time advances, custom time, midnight, and advancing automatic time. It requires finite HDR, bounded solar calculations, no windows/cache writes and moving water while sunset is held. It is included in `macos/test-current.sh`.

[Dated validation](daylight-controls-report-2026-11-06.json) also records native menu/picker checks: applied sunset, saved 18:30, canceled an edit without changing the setting, and restored automatic time. [Held sunset capture](daylight-controls-sunset.png).
