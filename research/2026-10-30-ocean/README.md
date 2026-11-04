# Ocean wallpaper research kit

This kit contains source-derived workload analysis, CPU reference experiments,
an experimental fused WebGPU kernel, and a macOS occlusion diagnostic.
It supports a renderer that changes with weather, time, location, and desktop visibility.

The source snapshot is `GodlyDonuts/web-ocean`, branch `feature/native-macos-wallpaper`,
commit **`8739f0793f84b96cb87a21558a117e1714184ad7`**.
The research did not change the repository snapshot or any remote branch.

## Evidence status

| Material | What it establishes | What it does not establish |
|---|---|---|
| CPU reference tests | Mathematical contracts and conservative mask behavior | macOS visibility accuracy or GPU speed |
| Spectral/geometry analysis | Source workload counts and analytic error bounds | Rendered equivalence or power savings |
| Actual-source JavaScript check | Counts from the repository's unchanged CDLOD functions | GPU vertex invocations or frame time |
| CPU fusion check | Packed-field equations, row ownership, and inverse-DFT agreement | WGSL compilation, GPU rounding, or race freedom |
| Fused WGSL candidate | A concrete integration candidate | **UNCOMPILED; GPU UNBENCHMARKED** |
| Swift diagnostic | Source for testing desktop-window occlusion | **UNCOMPILED; NOT RUN ON macOS** |

No GPU timings, macOS measurements, energy measurements, or visual-quality results
were produced in the authoring environment. Workload reductions are not FPS claims.
Python calculations use binary64 except where float32 assignment is explicitly reproduced.

## File map

| Path | Contents |
|---|---|
| `prototypes/demand_planner.py` | Conservative visibility masks, bloom dependency pullback, temporal reconstruction, spectrum blending, and direction conventions |
| `prototypes/run_experiments.py` | Generates CPU experiment JSON and both figures |
| `tests/test_reference.py` | Independent checks of the reference model's contracts |
| `prototypes/spectral_geometry_analysis.py` | Spectral support, dispersion, interpolation bounds, derivative response, traffic counts, and Python CDLOD reproduction |
| `prototypes/validate-cdlod-count.mjs` | Extracts and runs unchanged camera/CDLOD functions from a supplied source checkout |
| `prototypes/fused_evolve_rows.wgsl` | Candidate that generates spectral fields directly into row-FFT workgroup memory |
| `prototypes/fused_evolve_rows_integration.txt` | Exact bindings, dispatch changes, accounting, and required GPU validation |
| `prototypes/check_fused_evolve_rows.py` | CPU equation, index-ownership, and direct-DFT comparison |
| `prototypes/OcclusionProbe.swift` | Static desktop-window mosaic diagnostic using public AppKit APIs |
| `prototypes/build-occlusion-probe.sh` | Builds and ad-hoc signs the diagnostic on macOS 26+ |
| `prototypes/OcclusionProbe-README.md` | Diagnostic behavior, test matrix, and limitations |
| `results/` | Generated JSON evidence; classification labels are part of each result |
| `figures/` | Visibility/bloom dependency and temporal reconstruction plots |

## Reproduce the CPU work

Run the commands below from this kit's root directory, `ocean-research/`.
Use Python 3.10 or newer. NumPy and Matplotlib are needed for the reference suite
and plots. The spectral/geometry and fusion-check scripts use only the standard library.

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install numpy matplotlib
python -m unittest discover -s tests -v
python prototypes/run_experiments.py
```

The experiment script writes `results/reference_experiments.json`,
`figures/visibility_bloom_dependencies.png`, and
`figures/temporal_reconstruction_error.png`. It uses a fixed random seed for
the complex-coefficient spectrum-transition experiment.

```sh
python prototypes/spectral_geometry_analysis.py --output results/spectral_geometry.json
python prototypes/check_fused_evolve_rows.py --output results/fused_evolve_rows_cpu_check.json
```

The first command reproduces the band limits and the default-camera node counts.
Its projected-grid counts are proposed geometry budgets, not equal-quality replacements.
The second checks equations and CPU FFT layout, and exits nonzero on a failed check.
Neither command executes a GPU shader.

## Optional actual-source JavaScript check

This additional check requires Node.js and an existing checkout of the source commit.
Supply its `js/main.js`; the script also reads the adjacent `js/wgsl/common.js`.
For example, if the source checkout is a sibling directory named `web-ocean`:

```sh
node prototypes/validate-cdlod-count.mjs \
  --source ../web-ocean/js/main.js \
  --commit 8739f0793f84b96cb87a21558a117e1714184ad7 \
  --output results/cdlod_actual_js.json
```

The script extracts the actual function text and records its hashes and line locations.
Only the GPU uniform-upload operation is replaced with a no-op.
The `--commit` argument is a provenance label; verify the supplied checkout separately.
At the pinned commit, the default 16:9 view selects 906 nodes and submits 1,855,488 triangles.
Those counts precede GPU clipping and rasterization. They are not visible-triangle counts.

## Validate the fused kernel on the target GPU

Read `prototypes/fused_evolve_rows_integration.txt` before integration.
The candidate keeps the existing 256-point FFT, frequency quantization,
eight-real-field packing, butterfly schedule, and column output layout.

Its resources are `simUBO`, `h0Buf`, `tmpA`, and `tmpB`, in bindings 0 through 3.
Dispatch `(256, 1, 6)` for the source's six cascades.
Keep the original path available for comparison and change one mechanism at a time.

1. Compile with WebGPU validation and inspect all shader/binding diagnostics.
2. Compare intermediate row results, then final displacement, derivatives, and moments.
3. Test fractional times, the 600-second wrap, choppiness changes, and spectrum refreshes.
4. Compare animated glitter, foam, and silhouettes at matching camera and output size.
5. Measure the old evolution-plus-row stages against the fused stage and the whole frame.

The source-level saving is 12 MiB of intermediate buffers and 24 MiB of explicit
read/write traffic per frame. Cache behavior and compiler register pressure can change
the benefit. The CPU check cannot predict either or promise bit-identical GPU output.

## Run the macOS occlusion diagnostic

Use macOS 26+ with Xcode Command Line Tools. The Swift source has not been compiled
or run here. From the kit root:

```sh
bash prototypes/build-occlusion-probe.sh
prototypes/build/OcclusionProbe.app/Contents/MacOS/OcclusionProbe --tiled > results/occlusion.jsonl
```

The app paints a static blue background behind desktop icons and ignores mouse input.
Use the **◫** menu to compare one window with a 4-by-3 mosaic per display,
record a snapshot, show labels, or quit. Run one instance at a time.
Quitting removes its windows; it does not change wallpaper settings or login items.

Test opaque and translucent windows, rounded corners, dragging, Spaces, Mission Control,
Stage Manager, fullscreen apps, multiple displays, display scaling, and sleep/wake.
Check event arrival and conservative behavior when an area becomes visible again.
See `prototypes/OcclusionProbe-README.md` for the complete workflow.

The reported visible-tile area is an upper bound, not an exact visible-pixel percentage.
A partly visible tile remains fully counted. This experiment does not establish that
macOS exposes an exact public per-pixel occlusion region for arbitrary windows.
If tested in an animated implementation, share one simulation across presentation tiles;
do not instantiate one ocean simulation or WebView per tile.
Measure WindowServer and total system energy as well as renderer GPU time.

## Interpretation limits

- Visibility-model inputs must already be confirmed opaque; window alpha alone is insufficient.
- Unknown, moving, or stale occluders are treated conservatively by the reference model.
- Bloom can require shaded HDR pixels behind an occluder; final visible area is not total demand.
- Wave fields are analytically recoverable at a new time; persistent foam requires separate handling.
- Hermite bounds are per harmonic amplitude, not errors in shaded pixels or foam coverage.
- Changing FFT resolution, finite differences, and statistical wave tails changes reconstruction.
- A fixed camera permits cached rays and anchors, not a permanently fixed inverse choppy surface.
- Weather/location fetching and a production renderer are outside this kit's implemented scope.

## Sources

- [Pinned repository](https://github.com/GodlyDonuts/web-ocean/tree/8739f0793f84b96cb87a21558a117e1714184ad7)
- [Renderer source](https://github.com/GodlyDonuts/web-ocean/blob/8739f0793f84b96cb87a21558a117e1714184ad7/js/main.js)
- [Simulation shaders](https://github.com/GodlyDonuts/web-ocean/blob/8739f0793f84b96cb87a21558a117e1714184ad7/js/wgsl/sim.js)
- [Apple: window occlusion state](https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.struct)
- [Apple: occlusion-state notifications](https://developer.apple.com/documentation/appkit/nswindow/didchangeocclusionstatenotification)
- [Apple: work when visible](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/WorkWhenVisible.html)
- [Johanson: projected-grid thesis](https://fileadmin.cs.lth.se/graphics/theses/projects/projgrid/)
- [Bruneton et al.: geometry-to-BRDF ocean representation](https://doi.org/10.1111/j.1467-8659.2009.01618.x)
- [Olano and Baker: LEAN Mapping and errata](https://userpages.cs.umbc.edu/olano/papers/lean/)
