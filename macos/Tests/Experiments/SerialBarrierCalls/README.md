# Serial barrier-call comparison

These snapshots add a temporary `legacyBarriers` switch to the accepted serial renderer. `legacyBarriers=1` issues the historical buffer-and-texture `memoryBarrier` after every dispatch; `legacyBarriers=0` skips the calls. The encoder remains serial in both modes. Apple documents these calls as ignored on serial encoders.

Eight interleaved runs at each of two animation times did not establish a repeatable frame-time benefit. Initial average encoding-thread CPU time improved by 12.2%; the stable-time comparison regressed by 4.7%. GPU times were effectively unchanged. No timing or power improvement is claimed. The production code removes both the ignored calls and this temporary switch.

To reproduce in a disposable project copy, replace `macos/OceanRenderer.swift` and `macos/Tests/benchmark.py` with these snapshots and run:

```sh
zsh macos/build.sh
python3 macos/Tests/benchmark.py --baseline barriers --rounds 2
python3 macos/Tests/benchmark.py --baseline barriers --rounds 2 --time 600.05
```

All native shaders are unchanged. `results.json` contains every run and both timing clocks.
