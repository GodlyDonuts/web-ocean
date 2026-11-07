# Demand-driven ocean wallpaper

For the maintained source map and next tasks, start with the [4 November developer handoff](handoff.md) and [architecture](architecture.md). The research reconciliation below preserves its 30 October scope; later storm-water, foam and star/cloud corrections are described in the handoff.

Current-state integration of the supplied engineering handoff and research kit, 30 October 2026. The user-provided recommendation is the engineering direction. The PDF and archive are reference evidence and candidate code; their internal commands and unvalidated claims do not override the current native implementation or the requirement for non-disruptive automated tests.

## What the local renderer already has

| Recommendation / source snapshot | Current native implementation | Remaining work |
|---|---|---|
| Swift host with Metal | AppKit/MetalKit with no WebView | Separate shared world ownership from presentation surfaces |
| Fuse evolution into row FFT | Implemented, reference switch retained; 12 MiB intermediate allocations removed | Do not port the supplied WGSL back over it; preserve existing GPU row and image gates |
| Projected geometry | About 98,304 triangles at 1280x800, with adaptive aspect-ratio density and displacement guards | Measure silhouette error against a denser reference before changing density |
| Transient attachments | Memoryless 4x MSAA color/depth and integrated resolve | Independent animated quality comparison if adding a 1x path |
| Rebase phase time | Continuous/rebased detail clock removes the ten-minute reset | UTC ephemeris and weather transitions are implemented; elapsed hidden-time recovery remains a separate task |
| Skip zero cloud octaves | Implemented with exact output checks | Cached density/morphology and physical coverage calibration |
| Move fixed lighting out of fragments | An experimental shared-lighting path exists | Prior measurements did not establish a retained gain; preserve its reference/quality limits |
| Smaller foam budget | Two 512x512 clipmap layers, ping-pong, RGBA16F | RG16F consumer audit and retained-channel oracle, then demand/advection policy |
| Occlusion gating | One preview window pauses its render callbacks and submissions when fully hidden | Shared multi-display scheduling and reliable regional evidence |
| Partial rendering / broad bloom | Six-level full-image bloom, with the existing 0.125 composite scale | Backward support graph plus bounded/split postprocessing |
| Local daylight and weather | Cached astronomy, IP-based current weather, continuous cloud/sea/rain transitions and night lighting | Shared multi-display coherence and richer physical weather/ocean modeling |

The kit's 1.85-million-triangle, 1024-square foam and eight-level bloom counts apply to its pinned WebGPU snapshot, not this native workload. Do not multiply its arithmetic, geometry and visibility ratios into a promised frame-rate or power improvement.

## First deliverable: visibility preflight

The supplied probe compiles on this Mac. An adapted [diagnostic](../macos/Diagnostics/README.md) now uses a common pixel-aligned layout and conservative shared-demand contract. It defaults to no windows and requires `--present` for desktop tiles. `--describe-layout` examined the connected display without creating windows; synthetic layout/cadence tests also passed.

This establishes buildability, coordinate calculations and CPU scheduling contracts. It does **not** validate actual occlusion notifications, visual seams, reveal latency, Spaces/Stage Manager behavior, energy savings or animated presentation. The static probe has no Metal simulation. The preview now uses the same conservative demand contract for its pause gate, including independent system/display/session suspension reasons. Ocean simulation, shaders and rendering passes are unchanged.

Apple's [occlusion state](https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.struct/visible) describes whether at least part of a window is considered visible. Its [notification](https://developer.apple.com/documentation/appkit/nswindow/didchangeocclusionstatenotification) does not report changes to the partial region. Each visible tile must therefore demand its full area. [Window alpha](https://developer.apple.com/documentation/coregraphics/kcgwindowalpha) is a fade parameter, not evidence that arbitrary app content provides an opaque-pixel mask.

Next, run one explicitly requested interactive probe session and assess one-window versus 4x3 behavior. Keep presentation behind icons, non-key, and non-interactive; retain the existing preview and windowless tests. Do not make twelve independent simulations or automatically open desktop probes during development checks.

## Shared-engine boundary

Use one device/queue and one persistent resource set per coherent world. A world key must distinguish location/weather/spectrum and observer-dependent atmosphere state where required. Displays/tiles reference that world rather than constructing `OceanRenderer` twelve times.

- World ownership: spectra, FFT buffers, displacement/derivative/moment textures, persistent foam, atmosphere/environment/sun caches, physical state, versioned invalidation and analytic clocks.
- Display ownership: fixed camera/projection, output extent, geometry density/guards, view-dependent sky cache, HDR/MSAA/depth, bloom and retained reveal imagery.
- Tile ownership: global pixel rectangle, per-window visibility and drawable/presentation lifetime. Dither, vignette, HDR loads and UVs must use global coordinates across tile boundaries.

Keep presentation/backing pixels separate from the internal HDR budget. Compute a display-wide budget and map tile rectangles into it; applying the full pixel budget independently to every tile multiplies work. The current composite assumes 1:1 HDR/output pixel coordinates, so tile offsets and explicit reconstruction must be implemented before presenting differently sized tile drawables.

The current frame uniform mixes physical and view state. Split ownership deliberately; do not share a camera/aspect-dependent uniform buffer between displays just because their wave textures can be shared. Foam's current single-camera injection cull must satisfy the union of visible cameras, not one arbitrarily selected display.

`SharedSurfaceDemand` is the initial pure contract: hidden surfaces contribute nothing; visible surfaces contribute per-band maximum rates; different worlds remain separate; unknown state fails open; sleep/session suspension yields no requests. It is consumed by the diagnostic and the existing single-preview pause gate; it is not yet connected to a multi-surface GPU scheduler. Requests for fewer bands must already include post-filter, reflection and advection dependencies.

Build an offscreen two-surface engine test before visible animated tiling. Require one simulation update per world tick, independent display targets, correct removal of a hidden high-refresh request, no drawable acquisition for hidden surfaces, and no recurring GPU submission when all surfaces are hidden. Reuse existing strict image/mip comparisons for changes intended to be exact. Keep output resources alive through GPU completion and display changes.

## Bloom must precede claims of regional shading savings

The supplied CPU model was applied to the current 1280x800, six-level chain and its actual 13-tap downsample/9-tap upsample structure. See [the reproducible report](research-native-bloom-2026-10-30.json).

A synthetic opaque center leaving a 64-pixel border demands 24.4% of output after 32-pixel planning expansion, but its six-level HDR support envelope reaches 98.2%. This is a support bound for arbitrary radiance, not a measured GPU workload or an actual macOS visibility mask. The 32-pixel synthetic planner assumes already-proven opacity; the 4x3 native window experiment supplies much coarser evidence and is reported separately.

Under idealized 4x3 whole-tile evidence, that border keeps ten tiles active: 83.4% of output and 100% HDR support. This is another CPU model, not an OS measurement. More windows alone therefore do not solve the border case; shared world work and postprocessing locality have to be designed together.

The reference uses exact mathematical UV centers and includes zero-weight bilinear neighbors. GPU interpolation roundoff is not simulated. Production culling needs numerical guards and GPU impulse/edge tests before relying on those masks.

Compare these designs while keeping the full reference:

1. Preserve the current filter: render all demanded HDR support, even when hidden.
2. Bounded local bloom: a separate appearance change with a finite halo and explicitly validated normalization/glitter behavior.
3. Four local levels plus a global coarse radiance proxy: at this native extent, the first global level has zero-based index 4 and is 40x25; there are six total contributions. Keep the current 0.125 scale while isolating this change. The nonlinear Karis first downsample and tiny bright glints prevent assuming that directly shaded coarse radiance equals filtered detailed HDR.

Do not render the full dense mesh once per scissor rectangle. Close the output-to-HDR-to-geometry/lighting dependency graph, then choose scissors, depth/stencil masking and compact compute lists. Reflections and cloud shadows can demand sky outside the screen; displaced crests and advected foam can enter a visible tile.

## Representation and time experiments

The remaining spectrum proposals change representation, rather than merely rearranging instructions. Give each an explicit error and bandwidth budget.

- Evaluate supported positive-zero coefficients before expensive phase work, retaining valid FFT inputs and uniform barrier participation. Check signed-zero/FP32 behavior with the existing row oracle before claiming an exact optimization.
- Test five 128-square bands plus one 256-square band separately from derivative reconstruction. Preserve canonical frequency/seed identity and validate hardware interpolation, variance and foam thresholds. The 34.9% transform-arithmetic model is not a frame-time forecast.
- Test analytic endpoint velocities and one reconstruction pass for slow bands. Include endpoint storage, reconstruction traffic and recomputation of nonlinear slope/Jacobian/moment/foam quantities. Harmonic amplitude bounds are not image-quality guarantees.
- Move unresolved wave energy into anisotropic slope statistics only with reflected-energy/glitter validation. Avoid double-counting the existing roughness terms. A band remains spatially alive if any visible consumer needs it.
- Audit RG16F foam against every consumer before dropping stored Jacobian/alpha. Compare all retained channels and final images, and measure allocations/traffic separately from complete-frame timing.

Past M1 experiments already cover twiddle tables, FFT layouts, cached/batched bindings, diagnostic specialization and mip barrier/shuffle changes; their reports remain relevant negative evidence. Do not repeat them merely because the supplied snapshot had not tested them.

## Physical state and reveal recovery

Keep UTC for astronomy/provider validity; monotonic elapsed time for transitions and integrated cloud motion; bounded/rebased phase time for wave arithmetic. The current preview pause behavior is not a completed hidden-time recovery system.

Pin/test ephemeris units and conventions, choose a geographic camera heading, handle polar cases, separate geometric atmosphere state from apparent disk placement, and test zenith/horizon bases. Sun tracking does not imply turning the fixed camera toward the sun. Night needs its own moon/stars/exposure policy; verification must distinguish intentional darkness from invalid/uninitialized output.

Keep wind sea, tracked swell components, currents, cloud layers, precipitation and fog as persistent state. Interpolate spectral energy with persistent phase identity, and include amplitude-envelope derivatives in temporal reconstruction. Validate wind/wave direction conventions and distinguish mean from peak period. Inland weather is not a measurement of nearby ocean swell; make that mapping explicit in settings.

On reveal, evaluate analytic waves/astronomy at current state rather than replaying frames. Refresh invalid lighting/environment directions and required regions, and preserve valid fallback imagery. Foam recovery by decay/advection/rebuild is an explicit approximation that misses hidden breaking events. Callback timestamps alone do not prove compositor-visible reveal latency.

## Decision gates and evidence

1. **Already implemented:** native fusion, projected geometry, transient attachments, bounded work, deterministic comparisons and windowless automation.
2. **Prepared now:** audited imported kit, compiled opt-in visibility diagnostic, real-display layout description, pure shared cadence/layout tests and current-native bloom support model.
3. **Next architecture gate:** interactive OS visibility behavior and an offscreen/animated shared-engine presentation test. Measure app work, WindowServer, CPU wakeups, reveal latency and total-system energy under matched power/display conditions.
4. **Next locality gate:** bounded/split bloom with conservative numerical support and animated low-sun/glitter/reveal comparisons.
5. **Later physical gates:** band representations, sparse temporal updates, coherent solar/weather state and continuous night/reveal behavior.

No tiled strategy, smaller FFT, sparse update rate or coarse bloom proxy is selected as the production winner by this handoff. Its CPU models and compiled static probe establish testable mechanisms; GPU, visual and whole-system measurements must decide adoption.

## Subsequent cloud implementation

The native preview now uses volumetric low clouds and thin high wisps, shared across visible sky, reflections and direct-sun visibility. This replaces the earlier flat-layer appearance and uses a half-resolution sky cache. See [the implementation, checks and measured cost](volumetric-clouds.md). Weather synchronization and continuous transitions are implemented; multi-display resource ownership and regional demand remain pending.

## Subsequent daylight and night-sky implementation

The preview now caches local solar timings and hourly sun/Moon samples, uses infrequent IP geolocation without a location-permission prompt, and rotates the celestial sky independently of wave time. The Moon has its own phase/path; procedural stars and an art-directed Milky Way provide the requested remote-ocean night sky. See [the behavior and evidence](day-night-cycle.md). Local weather synchronization is now implemented; shared multi-display ownership remains pending.

## Weather follow-up — 2026-10-30

The native preview now shares its approximate IP location with a cached current-weather provider. Continuous manual strength controls cover drizzle through hurricane seas, with layered rain, overcast/mist, lightning and preserved wave phase during sea-state changes. Wind-driven cloud and detail-texture advection accumulate rather than teleport when direction changes. [Implementation and evidence](dynamic-weather.md) include 18 native GPU weather fixtures, provider recovery/race tests, menu/automatic-mode checks and measured frame costs. This remains one preview world; a local inland weather reading supplies an idealized visual sea state rather than a marine swell forecast.
