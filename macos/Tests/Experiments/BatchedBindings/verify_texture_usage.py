#!/usr/bin/env python3
"""Exact GPU comparison of render-target usage flags, including all bloom levels."""
import argparse
import json
from pathlib import Path
import subprocess
parser=argparse.ArgumentParser()
parser.add_argument('--batched-bindings',action='store_true',help='Isolate immutable binding lists instead of texture usage flags')
args=parser.parse_args()
flag='batchBindings' if args.batched_bindings else 'narrowTextureUsage'
root = Path(__file__).resolve().parents[2]
app = root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
output = root/('macos/build/quality-batched-bindings' if args.batched_bindings else 'macos/build/quality-texture-usage')
output.mkdir(exist_ok=True)
report = output/'report.json'
report.unlink(missing_ok=True)
cases = {
    'sunset':{}, 'phase45':{'time':45}, 'phase120':{'time':120},
    'daylight':{'sunElev':35,'clouds':0.1},
    'storm':{'windSpeed':12,'swellHs':2.5,'clouds':1,'veil':1,'haze':8},
    'clear':{'clouds':0,'veil':0}, 'low_only':{'veil':0}, 'high_only':{'clouds':0},
    'ultrawide':{'renderWidth':1908,'renderHeight':537,'time':30},
    'portrait':{'renderWidth':759,'renderHeight':1349,'time':15},
    'index_fallback':{'renderWidth':62,'renderHeight':16384,'time':5},
    'stable':{'time':600.05}, 'month':{'time':2592000},
    'narrow_stable':{'renderWidth':253,'renderHeight':4048,'time':600.05},
}
if args.batched_bindings:
    cases.update(resize_return={'resizeSequence':1},resize_narrow={'resizeSequence':2,'time':600.05},unfused_evolution={'fusedEvolution':0},unfused_mips={'fusedMips':0},
        all_reference_paths={'fusedEvolution':0,'fusedMips':0,'verboseBindings':1,'dynamicUniforms':1,'fullSky':1,'sharedLighting':1},
        stable_reference_paths={'fusedEvolution':0,'fusedMips':0,'time':600.05,'renderWidth':759,'renderHeight':1349})
results=[]
for name,settings in cases.items():
    captures=[]; paths=[]
    for enabled in (False,True):
        path=output/f'{name}-{int(enabled)}.rgba16f'
        paths.append(path)
        for suffix in ('','.bgra8','.mips','.clouds','.bloom'): Path(str(path)+suffix).unlink(missing_ok=True)
        query={'fixedDt':'0.0333333333','dump':str(path),'dumpMips':1,'dumpClouds':1,'dumpBloom':1,flag:int(enabled),**settings}
        process=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in query.items())],cwd=root,capture_output=True,text=True,timeout=90)
        assert process.returncode==0,process.stdout+'\n'+process.stderr
        diagnostic=[line.removeprefix('Ocean diagnostics: ') for line in process.stdout.splitlines() if line.startswith('Ocean diagnostics: ')]
        assert len(diagnostic)==1
        data=json.loads(diagnostic[0]);assert not data['errors'] and data['batchedBindings' if args.batched_bindings else flag]==enabled
        assert data['renderTextureUsage']==([5]*8 if enabled or args.batched_bindings else [23]*8), data['renderTextureUsage']
        if 'resizeSequence' in settings:
            expected=[[1280,800],[759,1349],[1907,537],[1280,800] if settings['resizeSequence']==1 else [253,4048]]
            assert data['verifiedResizeLayouts']==expected, data['verifiedResizeLayouts']
        captures.append({suffix:Path(str(path)+suffix).read_bytes() for suffix in ('','.bgra8','.mips','.clouds','.bloom')})
    counts={}
    for suffix in captures[0]:
        a,b=captures[0][suffix],captures[1][suffix]
        assert a and len(a)==len(b),(name,suffix,len(a),len(b))
        assert a==b,(name,suffix,sum(x!=y for x,y in zip(a,b)))
        counts[suffix or 'HDR']=len(a)
    result={'case':name,'comparedBytes':counts,'changedBytes':0,'width':data['width'],'height':data['height'],'verifiedResizeLayouts':data['verifiedResizeLayouts']}
    results.append(result);print(json.dumps(result),flush=True)
    for path in paths:
        for suffix in captures[0]: Path(str(path)+suffix).unlink()
report.write_text(json.dumps({'passed':True,'flag':flag,'cases':results},indent=2)+'\n')
print('PASS: HDR, display, wave/foam mips, sky/environment/sun and all six bloom levels are bit-identical.',flush=True)
