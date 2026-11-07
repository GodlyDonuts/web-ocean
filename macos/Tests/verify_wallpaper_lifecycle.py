#!/usr/bin/env python3
"""Windowless startup-before-first-frame and recreated-view regression."""
import json,os,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[2];out=root/'macos/build/wallpaper-lifecycle';out.mkdir(exist_ok=True)
report=out/'verification.json';report.unlink(missing_ok=True)
env=os.environ.copy();env.update(MTL_DEBUG_LAYER='1',MTL_SHADER_VALIDATION='1')
p=subprocess.run([str(root/'macos/build/Ocean.app/Contents/MacOS/Ocean'),'--verify',
 '--query=fixedDt=0&dayNight=0&testIdleDiagnostics=1&testSurfaceSizing=1'],capture_output=True,text=True,env=env,timeout=120)
(out/'startup.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stdout+p.stderr
d=[json.loads(s.removeprefix('Ocean diagnostics: ')) for s in p.stdout.splitlines() if s.startswith('Ocean diagnostics: ')]
assert len(d)>=2,'Need both idle startup and rendered-frame diagnostics'
idle,rendered=d[0],d[-1]
assert idle['frames']==0 and idle['cloudCacheWidth']==0 and idle['cloudCacheHeight']==0 and idle['width']==0
assert rendered['frames']>=8 and rendered['width']>0 and rendered['cloudCacheWidth']>0
assert 'PASS: replacement surface retains' in p.stdout
for v in d:assert v['offscreen'] and v['windowCount']==0 and v['activationPolicy']==2 and not v['errors']
report.write_text(json.dumps({'passed':True,'idle':idle,'rendered':rendered,'scope':'No windows; diagnostics before first scene allocation and replacement drawable sizing with unchanged HDR dimensions. Actual OS visibility/login requires interactive testing.'},indent=2)+'\n')
print('PASS: zero-frame diagnostics, first render, replacement drawable sizing, zero windows')
