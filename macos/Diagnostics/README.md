# Desktop visibility experiment

This is a separate static AppKit diagnostic adapted from the supplied research kit. The ocean shading and simulation are unchanged. The preview uses the same shared-demand contract for its single-window pause gate. The diagnostic compiles for macOS 13+, and was compiled/tested on macOS 26.7. No animated shared engine is implemented by this tool.

Build and inspect the connected displays without creating any windows:

```sh
zsh macos/Diagnostics/build-occlusion-probe.sh
macos/build/OcclusionProbe.app/Contents/MacOS/OcclusionProbe --describe-layout
macos/build/OcclusionProbe.app/Contents/MacOS/OcclusionProbe --describe-layout --single
```

`npm run macos:probe:layout` runs the windowless 4x3 description. Default/help also create no windows. The description checks planned layout only; it reports `visibilityMeasured: false`, the actual application window count, and the prohibited activation policy. The pixel sizes are nominal AppKit backing dimensions; macOS display scaling can differ from the panel-native hardware mode. No screen capture or other-app window enumeration is used.

The visible experiment is an explicit opt-in:

```sh
macos/build/OcclusionProbe.app/Contents/MacOS/OcclusionProbe --present --tiled --duration=60 > macos/build/occlusion-tiled.jsonl
```

It paints static blue tiles at desktop level behind icons for 60 seconds. It ignores mouse input and does not activate foreground windows. The menu-bar **◫** control switches between one window and 4x3, toggles labels, logs a snapshot, or quits. Quitting removes the diagnostic windows; wallpaper preferences and login items are unchanged. `--duration=0` keeps it open until manually quit. Run one instance at a time. No visible experiment is launched by builds, automated tests, or `--describe-layout`.

Test one-window and 4x3 modes with an opaque app window, translucent content, rounded corners, dragging/reveals, fullscreen, Spaces, Mission Control, Stage Manager, display scale/hot-plug changes, and sleep/session transitions. Check `actualFrameMatchesPlanned`, each tile's occlusion transitions, and reveal behavior. A partially visible tile remains fully demanded. Window fade alpha is not used to invent opaque rectangles.

The log's `sharedRequestedHz` and six `sharedRequestedWaveBandHz` values come from `SharedSurfaceDemand`, a pure scheduling contract. They are requests for a future shared engine, not measured simulation updates. The static probe submits no Metal command buffers; AppKit and WindowServer may still consume resources. Its visible-tile area is an upper bound, not an exact visible-pixel mask. Compare WindowServer and whole-system energy before selecting a tiled presentation architecture.

`DisplayTileLayout` shares rounded pixel boundaries, supplies top-left local pixels plus AppKit/Quartz coordinates, and drops zero-area cells on tiny extents. Unit tests cover 72 layouts, 400 placements, negative origins, differing scales, odd pixel sizes, portrait/ultrawide layouts, invalid input and conservative shared cadence. `SharedSurfaceDemand` ignores fully hidden surfaces, takes per-band maxima across visible surfaces of the same world, separates distinct worlds, fails open on unknown visibility/invalid band masks, and suspends all demand during sleep or inactive sessions.

These contracts do not discover opacity or close the render dependency graph. Callers must include bloom, reflection, displaced geometry and foam-advection support before requesting fewer bands or pixels. The native preview feeds one surface into this policy and now handles system sleep, display sleep and inactive-session suspension independently. See [the integration roadmap](../../docs/engineering-roadmap.md) for the shared Metal engine and bloom work that remains.
