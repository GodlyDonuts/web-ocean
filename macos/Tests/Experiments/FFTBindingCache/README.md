# FFT resource-list caching experiment

This archived controller reuses the two FFT resource lists, with `rebuildFFTResources=1` selecting the original per-frame construction. The production app retains the original construction.

Eight alternating runs on this Apple M1 showed no reliable benefit. CPU frame-encoding mean rose from 0.725 ms to 0.761 ms in this comparison, while GPU differences were small. This does not establish a general rule about array caching or explain the timing difference. `benchmark.json` preserves the measurements; the archived controller preserves the tested implementation.
