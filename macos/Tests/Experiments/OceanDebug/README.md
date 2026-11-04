# Rejected ocean debug-path specialization

The fragment shader contains an early diagnostic return and a late block selecting eight diagnostic displays. The candidate wraps them with OCEAN_DEBUG_VIEW bits 1 and 2, while the normal launch path selects mask 2: omit the early return and preserve the late block. Nonzero dbg settings and archived reference shaders retain mask 3. Verification-only oceanDebugMask overrides permit reproducing masks 0/1. pruneOceanDebug=0 always uses the original full shader. No extra runtime shader variants are created.

Mask 0 removed both blocks and failed the first sunset comparison: 9 changed half-float HDR values and one changed display byte. Mask 1 retained the early block but removed the late block; four scenes matched before storm failed with 2 changed HDR values. Mask 2 removed only the early block and passed all 24 comparisons: fourteen scene/viewport/uptime cases, all eight diagnostic displays, and stable-time/very-narrow diagnostic checks. Every bloom level, HDR/display, wave/foam mip and cloud intermediate was compared as raw bytes. No tolerances were relaxed.

Eight interleaved full-frame benchmark runs for the passing mask 2 did not show a useful GPU improvement: mean changed by approximately -0.14%, median worsened 0.42%, p95 worsened 0.74%. No speed or energy improvement is claimed. The candidate was removed and all accepted production source hashes restored.

Snapshots expect original repository paths: OceanRenderer.swift under macos/, OCEAN.metal under macos/Shaders/, both Python drivers under macos/Tests/, and test.sh under macos/. In a disposable checkout, build and run `python3 macos/Tests/verify_ocean_debug.py --mask 2`, then `python3 macos/Tests/benchmark.py --baseline oceandebug --rounds 2`. Masks 0 and 1 intentionally fail the strict gate. Production no longer accepts these experimental flags.

Measurements, failed comparisons and restoration hashes are in docs/optimization-report-2026-10-23-ocean-debug.json.
