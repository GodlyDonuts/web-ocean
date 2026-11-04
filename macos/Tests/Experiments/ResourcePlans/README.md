# Rejected immutable binding-list experiment

The candidate prebuilt resource arrays for wave evolution/FFT, cloud passes, ocean drawing, visible sky, bloom and compositing. Ping-pong foam had one list per destination; viewport-dependent lists were rebuilt after resizing. `resourcePlans=0` used the original lazy array expressions. Shader code, binding indices and call order were unchanged.

Twenty strict comparisons passed, including two in-process viewport resize sequences and four unfused/reference configurations. The archived `quality.json` includes every byte count and observed resize sequence. Sixteen interleaved full-frame runs did not establish a repeatable CPU improvement: default mean thread CPU encoding improved 2.1%, but stable-time mean increased 0.46%. GPU changes were effectively flat. The extra production caching code was removed.

These snapshots expect their original repository paths. To reproduce in a disposable checkout, place OceanRenderer.swift at macos/OceanRenderer.swift, both Python drivers under macos/Tests/, and test.sh under macos/. Build the candidate, then run `python3 macos/Tests/verify_texture_usage.py --resource-plans` and `python3 macos/Tests/benchmark.py --baseline resourceplans --rounds 2` (add `--time 600.05` for stable time). The test driver uses verification-only resizeSequence=1/2 hooks and checks actual layouts. Production sources no longer accept these experimental flags.

Full timing data and restoration hashes are recorded in docs/optimization-report-2026-10-23-resource-plans.json. A next experiment should test batched Metal resource setters rather than retaining the same per-resource API calls.
