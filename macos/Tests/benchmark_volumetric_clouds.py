#!/usr/bin/env python3
"""Sequential headless ABBA frame timing; no window or energy claims."""
import argparse
import json
from pathlib import Path
import statistics
import subprocess

root=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser()
p.add_argument('--baseline-app',type=Path,required=True,help='Saved pre-change app bundle')
p.add_argument('--rounds',type=int,default=1)
a=p.parse_args()
assert a.rounds>0
out=root/'macos/build/volumetric-clouds'
old=a.baseline_app.resolve()/'Contents/MacOS/Ocean'
new=root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
assert old.is_file() and new.is_file()
runs=[]
for round_id in range(a.rounds):
 for optimized in ([False,True,True,False] if round_id%2==0 else [True,False,False,True]):
    path=out/f'benchmark-{len(runs)}.json';path.unlink(missing_ok=True)
    query={'frames':180,'fixedDt':1/30,'time':5,'report':path}
    app=new if optimized else old
    process=subprocess.run([str(app),'--benchmark','--query='+'&'.join(f'{k}={v}' for k,v in query.items())],text=True,capture_output=True,timeout=90)
    assert process.returncode==0,process.stdout+process.stderr
    d=json.loads(path.read_text())
    assert d['offscreen'] and d['windowCount']==0 and d['activationPolicy']==2 and not d['errors']
    runs.append({'volumetric':optimized,**d})
    print(json.dumps({'volumetric':optimized,'gpuMeanMs':d['gpuMeanMs'],'gpuMedianMs':d['gpuMedianMs'],'gpuP95Ms':d['gpuP95Ms']}),flush=True)
summary={}
for label,flag in [('layered',False),('volumetric',True)]:
 group=[d for d in runs if d['volumetric']==flag]
 summary[label]={k:statistics.median(d[k] for d in group) for k in ['gpuMeanMs','gpuMedianMs','gpuP95Ms','cpuEncodeMeanMs']}
report={'scope':'Ordinary unprofiled command-buffer times on this Mac, warmup excluded; appearance and cached sky resolution intentionally differ. No whole-system energy or WindowServer measurement.','runs':runs,'summary':summary}
(out/'performance.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(summary),flush=True)
