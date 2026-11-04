# Storm crests, night foam and the camera waterline

The black region during an overtaking storm wave was a coverage failure: the near edge of the projected ocean grid could be displaced through the camera, exposing the cleared, scissored sky cache below the horizon. It was not simply insufficient night exposure.

The existing grid now spends its near guard rows on a patch that extends behind the camera. Triangle count is unchanged. Raised crests use the rasterized surface footprint for slope filtering instead of the divergent mean-plane approximation. Their Fresnel calculation also retains the local surface normal when the crest is above the eye.

A single GPU thread samples the six displacement cascades and approximately inverts horizontal chop to estimate the surface height at the fixed camera. Its 16-byte state drives a shared water scattering background and distance absorption when the camera is submerged. Uncovered downward rays see water radiance instead of an unrendered sky cache. Stars and falling rain fade out under the waterline. This is a lightweight height-field/volume treatment, not a simulation of overturning breakers or underwater caustics. The production camera remains fixed; the low-eye-height override is limited to offscreen verification.

Night foam now receives the same directional cinematic fill as the wave body. Foam retains a cool, nearly neutral diffuse color and varies with wave orientation. Foam coverage fades on the underside of overtaking crests instead of painting their back surfaces with a flat gray layer.

The camera sampling dispatch shares the existing compute encoder. There are no additional render passes or textures; the sole extra persistent allocation is the 16-byte GPU state buffer.

Run `python3 macos/Tests/verify_night_water.py` after `zsh macos/build.sh`. It checks six storm phases, raised crests, foam, rain, clear weather, daytime, portrait, and synthetic low-eye-height submerged views under Metal API/shader validation. These runs create no windows, make no location/network requests and write no user astronomy cache. The existing coverage suite also checks narrow, portrait, ultrawide and extreme-height targets.

[Before/after](night-water-comparison.png) · [Regression evidence](night-water-report-2026-10-30.json) · [Performance samples](night-water-performance-2026-10-30.json).

The regression now runs on a fresh checkout without local before captures. It creates a before/after montage only if optional historical before images exist; absence of those images does not skip any current rendering assertions.
