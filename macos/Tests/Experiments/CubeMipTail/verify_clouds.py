#!/usr/bin/env python3
"""Exact cloud comparisons including all reflection directions and mip levels."""
import argparse
import json
from pathlib import Path
import subprocess

parser=argparse.ArgumentParser()
parser.add_argument('--cube-mips',action='store_true',help='Isolate fused cube mips, including ocean reflections and incremental face refresh')
args=parser.parse_args()
root=Path(__file__).resolve().parents[2]
app=root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
output=root/('macos/build/cube-mip-quality' if args.cube_mips else 'macos/build/cloud-quality');output.mkdir(exist_ok=True)
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
results=[]
for name,settings in cases.items():
    captures=[]
    runs=[]
    for baseline in [True,False]:
        path=output/f'{name}-{"reference" if baseline else "optimized"}.rgba16f'
        query={'fixedDt':0,'fullSky':1,'skyOnly':1,'dumpClouds':1,'dump':path,'skipCloudOctaves':0 if baseline else 1,**settings}
        if args.cube_mips:
            query.update(fixedDt='0.0333333333',skyOnly=0,skipCloudOctaves=1,fusedCubeMips=0 if baseline else 1)
        process=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in query.items())],text=True,capture_output=True,timeout=90)
        if process.returncode:raise RuntimeError(process.stdout+'\n'+process.stderr)
        diagnostics=json.loads(next(line.removeprefix('Ocean diagnostics: ') for line in process.stdout.splitlines() if line.startswith('Ocean diagnostics: ')))
        assert not diagnostics['errors']
        if args.cube_mips: assert diagnostics['fusedCubeMips']==(not baseline)
        else: assert diagnostics['skipCloudOctaves']==(not baseline)
        runs.append({'reference':baseline,'fixedDt':query['fixedDt'],'skyOnly':query['skyOnly'],'fusedCubeMips':diagnostics['fusedCubeMips'],'elapsed':diagnostics['elapsed'],'frames':diagnostics['frames']})
        captures.append([path.read_bytes(),Path(str(path)+'.bgra8').read_bytes(),Path(str(path)+'.clouds').read_bytes()])
    for index,kind in enumerate(['HDR','display','sky/environment/sun']):
        assert captures[0][index]==captures[1][index], f'{name}: {kind} data changed'
    result={'case':name,'settings':settings,'width':diagnostics['width'],'height':diagnostics['height'],'stableDetails':diagnostics['stableDetails'],'comparedHDRBytes':len(captures[0][0]),'comparedDisplayBytes':len(captures[0][1]),'comparedCloudBytes':len(captures[0][2]),'changedBytes':0}
    if args.cube_mips: result['runs']=runs
    results.append(result);print(json.dumps(result),flush=True)
(output/'report.json').write_text(json.dumps({'passed':True,'comparison':'cube-mips' if args.cube_mips else 'cloud-octaves','cases':results},indent=2)+'\n')
print('PASS: full-sky HDR, display, cached sky, six reflection faces/all mips and sun visibility match exactly.',flush=True)
