# Rejected batched Metal resource bindings

ResourceBindings.swift prepared sparse nullable buffer/texture/sampler arrays with the original shader slot indices. Compute and fragment stages used setBuffers/setTextures/setSamplerStates batches; ocean vertex bindings stayed selective. The two fused wave mip dispatches each bound fifteen textures through one API call. Foam ping-pong had separate tables, and screen-dependent tables refreshed after resizing. batchBindings=0 lazily used the original per-resource setters. Verbose binding mode deliberately retained its original individual calls.

Twenty exact image/intermediate comparisons passed, including two repeated resize sequences and unfused paths. API and shader validation passed for a stable-time clear-sky resize sequence ending in the narrow viewport guard.

Twenty-four interleaved benchmark runs did not establish consistent CPU savings. The initial in-process comparison suggested a 3.8% mean thread CPU reduction. A separately built, source-identical accepted executable reduced possible fallback-path bias: default improved 1.95%, but stable-time worsened 3.34%. GPU time was effectively unchanged. The candidate was rejected; all accepted production files were restored.

To reproduce in a disposable checkout, place OceanRenderer.swift, ResourceBindings.swift, build.sh, and test.sh under macos/ and both Python files under macos/Tests/. Run the build script and `python3 macos/Tests/verify_texture_usage.py --batched-bindings`. ReferenceOceanRenderer.swift is the accepted renderer snapshot for a separate app build: compile it with the normal supporting Swift files, excluding ResourceBindings.swift, and copy the normal Info.plist and unchanged Shaders into that app. Run `python3 macos/Tests/benchmark.py --baseline batchbindings --rounds 2 --reference-app /absolute/path/to/reference.app/Contents/MacOS/Ocean`; add `--time 600.05` for stable time.

The archived test uses verification-only resizeSequence=1/2 and checks all observed layouts. Production no longer accepts these experimental flags. Full timing data, quality results and restoration evidence are in docs/optimization-report-2026-10-23-batched-bindings.json.
