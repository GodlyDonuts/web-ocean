# Desktop host: scope and verification

The retained change is a native desktop host around the established Metal ocean. It creates a borderless, click-through window at desktop level for each selected display and exposes controls through a menu bar item. `--preview` retains the original development window. A single visible view drives the frame clock; the renderer shares one FFT simulation, environment and HDR scene, and composites the result to each visible display with aspect-fill mapping around the horizon.

## Scope cleanup

The initial PR also introduced gulls, randomly scheduled waterspouts, aurora, meteors, bioluminescent foam, synthetic comet apparitions, noctilucent clouds, green flashes, eclipse/corona rendering, halos, rainbows/moonbows and procedural sun shafts. Those additions were not needed for the requested daylight/weather ocean and are removed, including their shaders, buffers, schedules, override options and gallery scenes. They are not merely hidden behind defaults. The scene's original cloud, star, ocean, rain and cached Sun/Moon shaders and ephemeris are restored from main. Real weather storms and the existing night-water/foam correction remain.

Future visual additions should be requested and reviewed individually against motion/performance captures. Randomly scheduled phenomena must not be described as real local astronomical or weather events.

## Correctness fixes

- Every replacement primary view gets its drawable size even when the shared scene dimensions do not change. Old view drivers pause and detach before their windows close, and the host releases its old primary-view reference.
- A zero grid-sampling count does not prove that the desktop is fully covered. Bounded rectangle subtraction confirms true coverage; narrow strips/gaps remain active at a throttled rate. Excessive fragmentation conservatively keeps rendering rather than assuming occlusion.
- Covered-desktop startup diagnostics tolerate an unallocated sky cache and untouched frame uniforms; logging no longer traps before the first frame. A windowless fixture exercises idle startup, first render and recreated-view sizing together.
- Gallery benchmarks delete old reports before running and validate exit codes, new reports, timing samples, zero windows, no GPU errors and no user-cache writes. A failed benchmark fails the gallery.
- The GPU workflow requires arm64. The renderer's native Float16 readbacks do not compile on Intel macOS runners. Automated tests remain windowless; the old screenshot/process-alive wallpaper smoke test is removed because it did not establish correct presentation.

The host's shared-frame approach resamples/crops one fixed scene, so it does not promise a panorama or independent compositions for different displays. The pause policy polls desktop coverage and responds to session/power/lock/screen-saver changes. Open at Login uses `SMAppService`; a local ad-hoc build is not a validated installed distribution.

## Verification matrix

Automated: CPU visibility/governor tests, recreated-primary drawable sizing without windows, failure-injected gallery tests, core GPU daylight/weather/waterline/lifecycle tests, and matched scene captures against main. Results for this change are recorded in the [cleanup validation](pr2-cleanup-validation.md).

Still requires a real interactive Mac setup: two monitors with differing aspect ratios/scales/refresh rates; main-display changes; connecting/disconnecting a display; toggling All Displays/Main Display Only; Space and fullscreen transitions; narrow desktop reveals; sleep/wake, lock/unlock and screensaver; installed/signed Open at Login; and whole-system power/reveal latency. Pure layout tests and hosted paravirtual Metal do not prove those behaviors.

Ocean now also installs/selects its native saver and maintains a system-wallpaper still on normal startup. See [automatic integration and regional rendering](regional-rendering.md) for private-store compatibility guards, restoration and the remaining interactive checks.
