#!/usr/bin/env python3
"""Read actual MSAA ocean occupancy, independently of sky color and shading.

An opaque diagnostic ocean is white, and the background is black. The region
below the sky scissor margin must contain complete ocean coverage.
"""
import array
import json
import math
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
app = root / 'macos/build/Ocean.app/Contents/MacOS/Ocean'
output = root / 'macos/build/coverage'
output.mkdir(exist_ok=True)
cases = {
    'standard': {'renderWidth':1280,'renderHeight':800,'time':5},
    'standard_storm': {'renderWidth':1280,'renderHeight':800,'time':90,'windSpeed':12,'swellHs':2.5},
    'portrait': {'renderWidth':759,'renderHeight':1349,'time':15},
    'stacked_portrait': {'renderWidth':512,'renderHeight':2048,'time':30},
    'narrow': {'renderWidth':256,'renderHeight':4096,'time':45},
    'narrow_storm': {'renderWidth':256,'renderHeight':4096,'time':90,'windSpeed':12,'swellHs':2.5},
    'extreme_phase_5': {'renderWidth':62,'renderHeight':16384,'time':5},
    'extreme_phase_45': {'renderWidth':62,'renderHeight':16384,'time':45},
    'extreme_phase_120': {'renderWidth':62,'renderHeight':16384,'time':120},
    'extreme_storm': {'renderWidth':62,'renderHeight':16384,'time':90,'windSpeed':12,'swellHs':2.5},
    'one_pixel_wide': {'renderWidth':1,'renderHeight':16384,'time':5},
    'ultrawide': {'renderWidth':1908,'renderHeight':537,'time':30},
}
results = []
for name, settings in cases.items():
    result = {'case':name,'settings':settings}
    for legacy in (True,False):
        path = output / f'{name}-{"legacy" if legacy else "guard"}.rgba16f'
        args = {'coverage':1,'fixedDt':'0.0333333333','dump':path,**settings}
        if legacy: args['legacyGuard'] = 1
        query = '&'.join(f'{k}={v}' for k,v in args.items())
        process = subprocess.run([str(app),'--verify',f'--query={query}'],capture_output=True,text=True,check=True,timeout=90)
        diagnostics = json.loads(next(line.removeprefix('Ocean diagnostics: ') for line in process.stdout.splitlines() if line.startswith('Ocean diagnostics: ')))
        assert diagnostics['offscreen'] and diagnostics['windowCount']==0 and diagnostics['activationPolicy']==2, 'Automated render must not create or activate windows'
        assert not diagnostics['errors']
        w,h = diagnostics['width'],diagnostics['height']
        assert diagnostics['physicalGuard'] == (not legacy and w*2<h)
        assert diagnostics['guardBoundsVerified'] == diagnostics['physicalGuard']
        values = array.array('H'); values.frombytes(path.read_bytes())
        assert len(values)==w*h*4
        # Positive half-float 1.0 is 0x3c00. Any partial MSAA coverage also fails.
        horizon = 0.5*(1-math.tan(math.radians(5.5))/math.tan(math.radians(29)))
        first_row = math.ceil(h*(horizon+0.1))
        missing = sum(values[(y*w+x)*4]!=0x3c00 for y in range(first_row,h) for x in range(w))
        result['legacyMissingPixels' if legacy else 'guardMissingPixels'] = missing
        result.update(width=w,height=h,checkedPixels=(h-first_row)*w)
    print(json.dumps(result),flush=True)
    assert result['guardMissingPixels']==0, f'{name}: uncovered ocean remains'
    results.append(result)
assert any(case['legacyMissingPixels']>0 for case in results), 'The regression test must reproduce an old mesh gap'
(output/'report.json').write_text(json.dumps({'passed':True,'cases':results},indent=2)+'\n')
print('PASS: complete lower-viewport MSAA ocean coverage in every tested case.',flush=True)
