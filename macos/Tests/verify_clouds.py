#!/usr/bin/env python3
"""Exact cloud comparisons including all reflection directions and mip levels."""
import argparse
import json
from pathlib import Path
import subprocess
import struct

parser=argparse.ArgumentParser()
parser.add_argument('--cleanup',action='store_true',help='Remove successful generated captures; retain failures for inspection')
parser.add_argument('--inactive-aa',action='store_true',help='Compare specialization of inactive cloud antialiasing')
args=parser.parse_args()
root=Path(__file__).resolve().parents[2]
app=root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
output=root/('macos/build/cloud-aa-quality' if args.inactive_aa else 'macos/build/cloud-quality');output.mkdir(exist_ok=True)
(output/'report.json').unlink(missing_ok=True)
cases={
    'sunset':{'time':5},
    'daylight':{'time':120,'sunElev':35,'clouds':0.5,'veil':0.8},
    'overcast':{'time':45,'clouds':1,'veil':1,'haze':10},
    'clear':{'time':15,'clouds':0,'veil':0},
    'portrait':{'time':15,'renderWidth':759,'renderHeight':1349},
    'ultrawide':{'time':30,'renderWidth':1908,'renderHeight':537},
    'stable_clock':{'time':600.05},
    'month_clock':{'time':30*86400},
    'stable_narrow':{'time':600.05,'renderWidth':62,'renderHeight':16384},
}
if args.inactive_aa:
    cases.update(low_only={'time':45,'clouds':0.4,'veil':0},high_only={'time':45,'clouds':0,'veil':0.36},clear_stable={'time':600.05,'clouds':0,'veil':0},low_stable={'time':600.05,'clouds':0.4,'veil':0},high_stable={'time':600.05,'clouds':0,'veil':0.36},fallback={'time':45,'testCloudAAMask':0},threshold={'time':15,'clouds':0.001,'veil':0.001})
if args.inactive_aa:
    cases.update(low_month={'time':30*86400,'clouds':0.4,'veil':0},high_month={'time':30*86400,'clouds':0,'veil':0.36},clear_portrait={'time':15,'clouds':0,'veil':0,'renderWidth':759,'renderHeight':1349},low_portrait={'time':15,'clouds':0.4,'veil':0,'renderWidth':759,'renderHeight':1349},high_ultrawide={'time':30,'clouds':0,'veil':0.36,'renderWidth':1908,'renderHeight':537},clear_narrow_stable={'time':600.05,'clouds':0,'veil':0,'renderWidth':62,'renderHeight':16384})
    already_checked={(3,3),(0,0),(1,1),(2,2),(0,3)}
    for compiled in range(4):
        for active in range(4):
            if (compiled,active) not in already_checked:
                cases[f'mask_{compiled}_active_{active}']={'time':45,'clouds':0.4 if active&1 else 0,'veil':0.36 if active&2 else 0,'testCloudAAMask':compiled}
def cloud_enabled(value):
    return struct.unpack('<f',struct.pack('<f',value))[0] > struct.unpack('<f',struct.pack('<f',0.001))[0]
results=[]
for name,settings in cases.items():
    captures=[]
    generated=[]
    runs=[]
    for baseline in [True,False]:
        path=output/f'{name}-{"reference" if baseline else "optimized"}.rgba16f'
        query={'fixedDt':0,'fullSky':1,'skyOnly':1,'dumpClouds':1,'dump':path,'skipCloudOctaves':0 if baseline else 1,**settings}
        if args.inactive_aa: query.update(skipCloudOctaves=1,pruneCloudAA=0 if baseline else 1)
        process=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in query.items())],text=True,capture_output=True,timeout=90)
        if process.returncode:raise RuntimeError(process.stdout+'\n'+process.stderr)
        diagnostics=json.loads(next(line.removeprefix('Ocean diagnostics: ') for line in process.stdout.splitlines() if line.startswith('Ocean diagnostics: ')))
        assert diagnostics['offscreen'] and diagnostics['windowCount']==0 and diagnostics['activationPolicy']==2, 'Automated render must not create or activate windows'
        assert not diagnostics['errors']
        if args.inactive_aa:
            mask = (1 if cloud_enabled(settings.get('clouds',0.4)) else 0) | (2 if cloud_enabled(settings.get('veil',0.36)) else 0)
            compiled = 3 if baseline else settings.get('testCloudAAMask',mask)
            expected = compiled if (mask & ~compiled)==0 else 3
            assert diagnostics['specializedSkyAAMask'] == compiled and diagnostics['skyAAMask'] == expected
        else: assert diagnostics['skipCloudOctaves']==(not baseline)
        paths=[path,Path(str(path)+'.bgra8'),Path(str(path)+'.clouds')]
        generated.extend(paths)
        runs.append({'reference':baseline,'specializedSkyAAMask':diagnostics['specializedSkyAAMask'],'skyAAMask':diagnostics['skyAAMask'],'stableDetails':diagnostics['stableDetails']})
        captures.append([p.read_bytes() for p in paths])
    for index,kind in enumerate(['HDR','display','sky/environment/sun']):
        assert captures[0][index]==captures[1][index], f'{name}: {kind} data changed'
    result={'case':name,'settings':settings,'width':diagnostics['width'],'height':diagnostics['height'],'stableDetails':diagnostics['stableDetails'],'specializedSkyAAMask':diagnostics['specializedSkyAAMask'],'skyAAMask':diagnostics['skyAAMask'],'comparedHDRBytes':len(captures[0][0]),'comparedDisplayBytes':len(captures[0][1]),'comparedCloudBytes':len(captures[0][2]),'changedBytes':0}
    if args.inactive_aa: result['runs']=runs
    if args.cleanup:
        for p in generated: p.unlink()
    results.append(result);print(json.dumps(result),flush=True)
(output/'report.json').write_text(json.dumps({'passed':True,'comparison':'inactive-cloud-aa' if args.inactive_aa else 'cloud-octaves','cases':results},indent=2)+'\n')
print('PASS: full-sky HDR, display, cached sky, six reflection faces/all mips and sun visibility match exactly.',flush=True)
