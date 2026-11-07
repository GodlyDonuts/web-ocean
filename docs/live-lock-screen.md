# Live Ocean on the lock screen

On macOS 26, Ocean uses a `com.apple.wallpaper` ExtensionFoundation extension to render the existing Metal scene in the system's wallpaper host. macOS places its clock and authentication controls above that surface. This replaces the earlier PNG-only lock background. The public `Ocean.saver` remains the fallback on older macOS releases.

A screensaver extension (`com.apple.screensaver`) alone did not provide the requested lock background. The attempted screensaver-as-wallpaper selection was rejected by macOS and is not retained. `OceanLiveWallpaper.appex` targets the dedicated wallpaper interface and advertises the same Ocean choice for desktop and idle use.

## Ownership and timing

The menu-bar app maintains IP location, weather, saved daylight selection and desktop coverage/power policy. It publishes small JSON files in `~/Library/Caches/OceanWallpaperLive/` only when their contents change. The directory is mode 0700 and files are 0600. The sandboxed extension has read-only access to this one cache directory and graphics-service lookups; it has no network, camera, microphone or location-services entitlement. It checks the environment and playback controls once per second, rather than reading JSON per frame.

The extension owns one ocean renderer per host process and presents its shared scene through remote Core Animation contexts. The controller hides its old desktop windows and stops their rendering only after the native setup has verified a running extension. Keeping the controller alive still provides settings, weather refresh and coverage throttling. The controller's allocated renderer resources are currently retained, although it submits no frames in native mode.

While unlocked, the extension obeys the controller's desktop FPS/pixel budget. OS lock/saver activity uses the usual adaptive battery and thermal policy instead of desktop coverage. Cached idle/preview contexts cannot force continuous full-rate rendering. Display-off/offline surfaces stop rendering. An awake locked surface overrides a host suspension or desktop coverage pause; hardware display state is checked at most twice per second. A paused controller is polled slowly so it can recover on reveal. No password, idle-lock delay, FileVault or authentication UI setting is changed.

The native timer must run at the chosen FPS. Driving 24 FPS through a 30 Hz timer created alternating 33/67 ms intervals and visible judder despite a correct average frame count. The timer now uses `1/FPS`, without a second timing gate. Remote-layer changes are flushed after submission. Manual native/saver hosts acquire every drawable directly through `CAMetalLayer.nextDrawable()`: `MTKView.currentDrawable` remains cached when its normal draw lifecycle is bypassed, and `releaseDrawables()` did not prevent reuse. Core Animation reported “Each CAMetalLayerDrawable can only be presented once” while submission counters kept advancing. Normal delegate-driven app views retain MTKView acquisition. Diagnostics distinguish submitted frames, successful GPU completions and drawable presentation callbacks; submission intervals alone do not prove visible playback or battery savings.

## Installation and restoration

Normal launches build/register the embedded `Contents/PlugIns/OceanLiveWallpaper.appex` and select it in both Desktop and Idle slots across the existing display/Space topology. The slot provider is the extension's bundle identifier, not the legacy screen-saver provider. Desktop placement and background colour need their own encoded options; Idle has empty options. The colour-space name is itself a binary-plist Data value.

Setup preserves unknown store fields, backs up before its first write, checks for concurrent changes, reloads the current user's registered WallpaperAgent and verifies its replacement, selected providers and an extension process at the expected executable path. Failed setup restores choices still owned by Ocean. Explicit user replacements survive restoration. A binary fingerprint triggers a host refresh after an update; setup defers while locked. Later launches preserve a deliberately selected different wallpaper unless Repair is invoked. The menu's restore command returns previous wallpaper/saver choices.

A static Ocean thumbnail is bundled for discovery/cold-start snapshots. Actual snapshot requests use a full GPU readback of the current scene. PNG refreshes do not overwrite an active native wallpaper provider.

## Private compatibility boundary

Apple has not documented the wallpaper extension's XPC protocol for third-party apps. The bridge loads the system WallpaperExtensionKit framework, exports the protocol and validates the runtime context/snapshot layouts. Settings models use its Codable wire format. The snapshot encoder supplies its IOSurface to WallpaperAgent through the actual XPC encoder. These compatibility points require revalidation after OS updates; a successful build alone is insufficient.

The executable must use `_NSExtensionMain` as its bootstrap, matching Xcode's app-extension product specification. The Swift `AppExtension.main` entry registers the implementation but does not by itself keep the service running. A build that enters Swift main directly exits before accepting the render connection.

The protocol declarations, settings wire models, XPC class whitelist and boilerplate stubs are adapted from [Aerial](https://github.com/AerialScreensaver/Aerial/tree/8b59840058217aaea73e1b4f6754899c7a4a0093/WallpaperExtension), under its MIT licence included in `macos/WallpaperExtension/Aerial-LICENSE` and the built extension. Store encoding follows the [PaperSaver source](https://github.com/AerialScreensaver/PaperSaver/tree/6d21cc89c01a84d86a17b62e9b8a6945c61ec5aa). No Aerial video player, decorative effects, network feeds or settings UI are included.

## Validation

- `zsh macos/test-unit.sh`: includes native store provider/options, all display/Space scopes, unknown fields, original linked choices and partial restore.
- `zsh macos/Tests/test-native-wallpaper.sh`: macOS 26 runtime canary for remote-context allocation/coding, snapshot layout/encoder, real settings-model decoding and the executable bootstrap. It creates no windows and changes no wallpaper preferences.
- `zsh macos/Tests/test-screensaver.sh`: public saver bundle/resource lifecycle and shared-display allocation.
- `python3 macos/Tests/verify_wallpaper_lifecycle.py`: windowless renderer lifecycle.
- Live diagnostics: `log show --last 5m --style compact --predicate 'subsystem == "local.wallpaper.ocean.live"'` records acquired surfaces, environment loading, submitted frames, successful GPU completions, presented drawables, renderer errors, lock state and submission pacing.

Native selection was observed automatically in System Settings as **Ocean / Live Metal ocean**. Actual frames advanced while locked. The user confirmed the ocean appeared and moved, then reported judder; the timer mismatch above was identified and corrected. A short visual check initially passed, but subsequent keyboard-lock and lid-close/wake testing revealed freezing; that short check was insufficient. The follow-up recovery build tracks explicit host locked mode, preserves omitted update fields, replaces stale Metal presentation views while retaining hosted context IDs, and handles hostDidWake immediately and after the two-second transition window. Display wake and host suspend/resume transitions also trigger recovery. The state/layer tests pass, but the subsequent user test still froze after two seconds on keyboard lock and became choppy after lid wake. This led to the cached-drawable error above and fresh layer acquisition for both manual hosts. Physical validation of that correction remains required. Consult the [dated validation report](native-wallpaper-report-2026-11-07.json) for the final pacing and visual-review outcome. No temperature, energy or battery-life reduction is claimed.
