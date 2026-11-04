# Rejected cloud density bound experiment

Conservative saturation bounds skipped remaining low-cloud shadow noise octaves. All saturation classifications were valid across 983,040 probes, but the stable-time shader changed unsaturated float32 results by up to 1.7881393432617188e-7. The strict equality gate failed; no performance benchmark was run. Production shaders and renderer were restored to their pre-experiment sources.

The archived Verification.swift expects the experimental SKY_BG.metal beside it to be installed temporarily before running; it is not part of the production test suite. results.json records every probe case.
