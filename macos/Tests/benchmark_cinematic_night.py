#!/usr/bin/env python3
"""Sequential ABBA comparison against an explicit saved pre-change native app."""
import argparse,json,statistics,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--baseline-app',type=Path,required=True);p.add_argument('--night-rounds',type=int,default=2);a=p.parse_args()
out=root/'macos/build/cinematic-night';out.mkdir(exist_ok=True)
report=out/'performance.json';report.unlink(missing_ok=True)
new=root/'macos/build/Ocean.app/Contents/MacOS/Ocean';old=a.baseline_app.resolve()/'Contents/MacOS/Ocean'
assert old.is_file() and new.is_file() and a.night_rounds>0
runs=[]
for scene,rounds,settings in [('starry_night',a.night_rounds,{'utc':1782014400,'heading':155,'clouds':0.12,'veil':0.05}),('day',1,{'utc':1793378400,'heading':180})]:
 for round_id in range(rounds):
  for optimized in ([False,True,True,False] if round_id%2==0 else [True,False,False,True]):
   path=out/f'budget-{len(runs)}.json';path.unlink(missing_ok=True)
   query={'dayNight':1,'latitude':40.7128,'longitude':-74.006,'timeZone':'America/New_York','frames':180,'fixedDt':1/30,'report':path,**settings}
   process=subprocess.run([str(new if optimized else old),'--benchmark','--query='+'&'.join(f'{k}={v}' for k,v in query.items())],capture_output=True,text=True,timeout=90)
   assert process.returncode==0,process.stdout+process.stderr
   d=json.loads(path.read_text())
   assert d['offscreen'] and d['windowCount']==0 and d['activationPolicy']==2 and not d['errors'] and d['dayNightActive'] and not d['profiled'] and d['solarCalculations']==1 and d['solarCacheWrites']==0
   runs.append({'scene':scene,'optimized':optimized,**d})
   print(json.dumps({'scene':scene,'optimized':optimized,'gpuMeanMs':d['gpuMeanMs'],'gpuMedianMs':d['gpuMedianMs'],'gpuP95Ms':d['gpuP95Ms']}),flush=True)
summary={scene:{label:{metric:statistics.median(r[metric] for r in runs if r['scene']==scene and r['optimized']==flag) for metric in ['gpuMeanMs','gpuMedianMs','gpuP95Ms','cpuEncodeMeanMs']} for label,flag in [('before',False),('after',True)]} for scene in ['starry_night','day']}
report.write_text(json.dumps({'scope':'Unprofiled command-buffer times, 180 frames/run with 60-frame warmup; matched scene/time/resolution/cadence, deliberately different sky appearance. No WindowServer, battery or energy measurement.','runs':runs,'summary':summary},indent=2)+'\n')
print(json.dumps(summary),flush=True)
