#!/usr/bin/env python3
"""Unprofiled steady-state day/night budget check, synthetic coordinates, no UI/network."""
import json
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[2]
out=root/'macos/build/day-night';out.mkdir(exist_ok=True)
app=root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
cases={'day':{'utc':1793378400,'heading':180},'starry_night':{'utc':1782014400,'heading':155,'clouds':0.12,'veil':0.05}}
runs=[]
for name in ['day','starry_night','starry_night','day']:
 path=out/f'budget-{len(runs)}.json';path.unlink(missing_ok=True)
 query={'dayNight':1,'latitude':40.7128,'longitude':-74.006,'timeZone':'America/New_York','frames':180,'fixedDt':1/30,'report':path,**cases[name]}
 p=subprocess.run([str(app),'--benchmark','--query='+'&'.join(f'{k}={v}' for k,v in query.items())],capture_output=True,text=True,timeout=90)
 assert p.returncode==0,p.stdout+p.stderr
 d=json.loads(path.read_text())
 assert d['offscreen'] and d['windowCount']==0 and d['activationPolicy']==2 and not d['errors'] and d['dayNightActive'] and d['solarCalculations']==1 and d['solarCacheWrites']==0 and not d['profiled']
 runs.append({'scene':name,**d})
 print(json.dumps({'scene':name,'gpuMeanMs':d['gpuMeanMs'],'gpuMedianMs':d['gpuMedianMs'],'gpuP95Ms':d['gpuP95Ms']}),flush=True)
(out/'performance.json').write_text(json.dumps({'scope':'Two day and two starry-night ordinary command-buffer runs, 180 frames each, first 60 excluded. Different scene states; this is a frame-budget check, not an isolated overhead or energy comparison. No WindowServer work measured.','runs':runs},indent=2)+'\n')
