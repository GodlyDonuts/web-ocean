# Contributing

Read the [handoff](docs/handoff.md), [architecture](docs/architecture.md) and [testing guide](docs/testing.md) before changing the renderer. The maintained implementation is `macos/`; use the browser files and research imports as references with their documented scope.

Build with `zsh macos/build.sh`. Run `zsh macos/test-unit.sh` for CPU changes and the relevant GPU fixtures for rendering changes. Before a substantial handoff, run `zsh macos/test-current.sh`. GPU verification requires a supported Mac; CI builds and CPU checks do not replace it. Keep automated runs windowless.

For visual changes, capture the same camera, UTC, weather, dimensions and simulation time before and after. Inspect animation as well as still images. For performance changes, preserve an explicit baseline app, use sequential alternating runs and report warmup, sample count, timings and quality differences. Do not present a historical image comparison as an equivalence check after intentional appearance changes.

Keep generated builds, raw captures, credentials, location/weather caches and local environments out of Git. Commit source, required assets and only curated evidence. Keep NASA/Gaia and imported research attribution intact. Use the branch/PR workflow appropriate to the change and explain the user-visible outcome, validation and remaining limits.

Bug reports should identify the native or browser version, Mac/GPU and macOS version, scene/time/weather, window shape, reproduction steps and an image or short recording if useful. Avoid posting personal IP addresses or saved location caches. Performance reports should include steady-state measurements rather than startup compilation time.
