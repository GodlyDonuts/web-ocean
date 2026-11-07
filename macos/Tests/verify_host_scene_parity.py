#!/usr/bin/env python3
"""Check that host changes preserve core HDR/display against an explicit baseline."""
import argparse,hashlib,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--baseline-app',type=Path,required=True);args=p.parse_args()
root=Path(__file__).resolve().parents[2];out=root/'macos/build/host-parity';out.mkdir(exist_ok=True)
report=out/'verification.json';report.unlink(missing_ok=True)
ny={'dayNight':1,'latitude':40.7128,'longitude':-74.006,'timeZone':'America/New_York'}
cases={'noon':{**ny,'utc':1793378400,'heading':180},
       'starry_night':{**ny,'utc':1782014400,'heading':155,'clouds':.12,'veil':.05},
       'storm_night':{**ny,'utc':1794283200,'heading':270,'storm':1,'time':60}}
results=[]
for name,settings in cases.items():
 for label,app in [('baseline',args.baseline_app.resolve()),('updated',root/'macos/build/Ocean.app')]:
  target=out/f'{label}-{name}';q={'fixedDt':0,'time':30,'dump':target,**settings}
  run=subprocess.run([str(app/'Contents/MacOS/Ocean'),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in q.items())],capture_output=True,text=True,timeout=120)
  (out/f'{label}-{name}.log').write_text(run.stdout+run.stderr)
  assert run.returncode==0,run.stdout+run.stderr
  diag=json.loads(next(s.removeprefix('Ocean diagnostics: ') for s in run.stdout.splitlines() if s.startswith('Ocean diagnostics: ')))
  assert diag['windowCount']==0 and diag['activationPolicy']==2 and diag['offscreen'] and not diag['errors'] and diag['solarCacheWrites']==0
 hashes={}
 for suffix in ['', '.bgra8']:
  a=Path(str(out/f'baseline-{name}')+suffix).read_bytes();b=Path(str(out/f'updated-{name}')+suffix).read_bytes()
  assert a and a==b,(name,suffix,'Scene changed')
  hashes['HDR' if not suffix else 'display']={'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()}
 results.append({'scene':name,'settings':settings,'exact':True,'outputs':hashes});print('PASS: exact HDR/display',name,flush=True)
report.write_text(json.dumps({'passed':True,'cases':results,'scope':'Matched offscreen captures against a separately built main app. Host modifications preserve these three core scenes; this does not test physical multi-monitor presentation.'},indent=2)+'\n')
