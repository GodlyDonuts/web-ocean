#!/usr/bin/env python3
"""Serial unprofiled weather workloads; never runs a visible preview."""
import json,statistics,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[2];out=root/'macos/build/weather'
new=root/'macos/build/Ocean.app/Contents/MacOS/Ocean';old=out/'Before.app/Contents/MacOS/Ocean'
scenes=[('before',old,{}),('after',new,{}),('after',new,{}),('before',old,{}),('hurricane',new,{'storm':1}),('building',new,{'weatherFrom':0,'weatherTo':1,'weatherChangeAt':1}),('building',new,{'weatherFrom':0,'weatherTo':1,'weatherChangeAt':1}),('hurricane',new,{'storm':1})]
runs=[]
for i,(label,app,settings) in enumerate(scenes):
 target=out/f'benchmark-{i}.json';target.unlink(missing_ok=True)
 query={'frames':180,'fixedDt':1/30,'time':30 if label!='building' else 0,'report':target,**settings}
 p=subprocess.run([str(app),'--benchmark','--query='+'&'.join(f'{k}={v}' for k,v in query.items())],text=True,capture_output=True,timeout=90)
 assert p.returncode==0,p.stdout+p.stderr
 d=json.loads(target.read_text());assert d['offscreen'] and d['windowCount']==0 and not d['errors']
 runs.append({'scene':label,**d});print(label,d['gpuMeanMs'],d['gpuP95Ms'],flush=True)
summary={label:{key:statistics.median(r[key] for r in runs if r['scene']==label) for key in ['gpuMeanMs','gpuP95Ms','cpuEncodeMeanMs']} for label in ['before','after','hurricane','building']}
(out/'performance.json').write_text(json.dumps({'runs':runs,'summary':summary,'scope':'Sequential 180-frame runs, 60 warmup frames excluded, 1280x800/30fps on this Mac. Before/after are identical fixed-weather reference workloads. Hurricane/building are additional current-app workloads, not equivalent-image comparisons. No validation, profiling, other rendering tests or visible Ocean preview during timing. Command-buffer times, not battery/WindowServer/energy measurement.'},indent=2)+'\n')
print(json.dumps(summary),flush=True)
