# Main-branch handoff validation — 4 November 2026

This record covers publication of the accumulated native Metal implementation and updated documentation/test entry points. Older feature reports retain their original dates and scope.

## Local results

Environment: Apple M1, macOS 26.7, Apple Swift 6.3.3; Python 3.11 with NumPy 2.3.5 and Pillow 11.3.0. Native minimum deployment target remains macOS 13; this run is not a test on every supported OS version.

| Check | Result |
|---|---|
| Native build, package and ad-hoc signing | Passed |
| CPU contracts (`test-unit.sh`) | All nine suites passed |
| Day/night GPU fixtures | 13 scenes passed, including polar cases, missing location and portrait |
| Weather GPU fixtures | 18 scenes passed, including transitions, storms, lightning and clock boundaries |
| Night-water GPU fixtures | 13 scenes passed, including foam, raised crests and submerged views |
| Mesh coverage | 12 viewport shapes passed, each checked against legacy/corrected paths |
| Windowless lifecycle | Three capture scenes, benchmark smoke and both startup-failure modes passed |
| Browser reference | `npm ci` and `npm run build` passed |
| Repository inventory and maintained links | 32 shader entries, required galaxy resources/checksum and all six maintained guides passed |
| Script syntax | Python compilation and shell syntax checks passed |
| Staged whitespace | Passed, with packed HDR imagery explicitly treated as binary |

The maintained GPU/CPU handoff command `zsh macos/test-current.sh` completed successfully. GPU fixture diagnostics reported zero windows, prohibited activation, no command errors and no user astronomy-cache writes. This was a deterministic validation run, not a new cinematic-quality or battery benchmark.

## Clean checkout

A disposable checkout was created from the staged publication files, excluding ignored build products, cached providers, local baseline app bundles, Python environments and Cargo targets. It built successfully from scratch. The night-water regression passed all 13 scenes with `historicalComparisonAvailable == false`, confirming that no before captures are required.

The initial hosted CI run exposed a CPU-test output-folder assumption: the celestial motion fixture writes `macos/build/celestial-motion/trajectory.json`. The CPU runner now explicitly creates that directory. All nine CPU suites then passed in the disposable checkout as well.

## CI and scope

[Repository checks](https://github.com/GodlyDonuts/web-ocean/actions/workflows/ci.yml) build the browser reference, check generated HTML parity and repository resources, then build the native app and run CPU contracts. Consult the run for the current commit for hosted status; local results above are independent of it.

The broad historical development suite, optional research reruns, movies and performance benchmarks were not all rerun for this documentation/publication handoff. Their earlier evidence remains under its original dates. Desktop wallpaper integration, multi-display presentation and total-system energy remain open work; no interactive app-launch loop was used here.
