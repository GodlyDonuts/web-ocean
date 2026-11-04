#!/usr/bin/env python3
"""Actual GPU cloud advection/evolution, accelerated timeline and wrap gates."""
import json, math, struct, subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[2]
out=root/'macos/build/cloud-realism';out.mkdir(exist_ok=True)
app=root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
scenes={'start':{'time':30},'wind_30s':{'time':60},'evolve_start':{'time':30,'windSpeed':0},'evolve_20m':{'time':1230,'windSpeed':0},'wrap_before':{'time':599.99},'wrap_after':{'time':600.01},'accelerated':{'time':0,'utc':1793394900,'cycleRate':300,'fixedDt':1/30,'verifyFrame':188},'equivalent':{'time':1850.000096485019}}
results={};buffers={}
for name,settings in scenes.items():
 path=out/f'{name}.rgba16f'
 query={'fixedDt':0,'dayNight':0,'sunElev':25,'clouds':0.5,'veil':0.5,'skyOnly':1,'fullSky':1,'dumpClouds':1,'dump':path,**settings}
 p=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in query.items())],capture_output=True,text=True,timeout=120)
 (out/f'{name}.log').write_text(p.stdout+p.stderr)
 assert p.returncode==0,p.stdout+p.stderr
 d=json.loads([s.removeprefix('Ocean diagnostics: ') for s in p.stdout.splitlines() if s.startswith('Ocean diagnostics: ')][-1])
 assert d['windowCount']==0 and d['offscreen'] and d['activationPolicy']==2 and not d['errors']
 n=d['cloudCacheWidth']*d['cloudCacheHeight']*8
 data=Path(str(path)+'.clouds').read_bytes()[:n]
 buffers[name]=[v[0] for v in struct.iter_unpack('<e',data)]
 assert all(math.isfinite(x) for x in buffers[name])
 results[name]=d
 print('PASS:',name,flush=True)
def difference(a,b):
 a,b=buffers[a],buffers[b]
 return math.sqrt(sum((x-y)**2 for x,y in zip(a,b))/max(1e-30,sum(x*x for x in a)))
metrics={'advection30sRelativeL2':difference('start','wind_30s'),'zeroWindEvolution20mRelativeL2':difference('evolve_start','evolve_20m'),'waveWrapRelativeL2':difference('wrap_before','wrap_after'),'acceleratedEquivalentRelativeL2':difference('accelerated','equivalent')}
assert metrics['advection30sRelativeL2']>0.01,metrics
assert metrics['zeroWindEvolution20mRelativeL2']>0.005,metrics
assert metrics['waveWrapRelativeL2']<0.005,metrics
assert metrics['acceleratedEquivalentRelativeL2']<0.001,metrics
(out/'motion-verification.json').write_text(json.dumps({'passed':True,'metrics':metrics,'scenes':results,'scope':'Fixed lighting isolates cloud motion; the late accelerated capture advances 188 frames from one UTC anchor. No windows, IP lookups or user-cache writes. Visual realism assessed separately from these numeric gates.'},indent=2)+'\n')
print('PASS:',json.dumps(metrics),flush=True)
