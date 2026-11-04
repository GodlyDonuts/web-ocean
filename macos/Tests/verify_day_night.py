#!/usr/bin/env python3
"""Deterministic GPU fixtures for offline sun/moon-driven lighting; no IP lookup/UI."""
from datetime import datetime
import json
from pathlib import Path
import struct
import subprocess
root=Path(__file__).resolve().parents[2]
app=root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
out=root/'macos/build/day-night';out.mkdir(exist_ok=True)
(out/'verification.json').unlink(missing_ok=True)
def utc(s): return datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
cases={
 'sunrise':{'utc':utc('2026-10-30T11:24:05Z'),'heading':110},
 'morning':{'utc':utc('2026-10-30T12:30:00Z'),'heading':110},
 'noon':{'utc':utc('2026-10-30T16:40:00Z'),'heading':180},
 'sunset':{'utc':utc('2026-10-30T21:45:00Z'),'heading':250},
 'twilight':{'utc':utc('2026-10-30T22:20:00Z'),'heading':250},
 'moonlit_night':{'utc':utc('2026-10-31T02:10:00Z'),'heading':60.0059176808,'clouds':0.15,'veil':0.1},
 'starry_night':{'utc':utc('2026-06-21T04:00:00Z'),'heading':155,'clouds':0.12,'veil':0.05},
 'dark_night':{'utc':utc('2026-11-10T04:00:00Z'),'heading':270},
 'polar_day':{'utc':utc('2026-06-21T12:00:00Z'),'latitude':89,'longitude':0,'timeZone':'UTC'},
 'polar_night':{'utc':utc('2026-12-21T12:00:00Z'),'latitude':89,'longitude':0,'timeZone':'UTC'},
 'portrait':{'utc':utc('2026-10-30T21:45:00Z'),'renderWidth':759,'renderHeight':1349},
 'fixed_reference':{'dayNight':0,'time':5},
 'missing_location':{'latitude':'','longitude':'','utc':utc('2026-10-30T12:00:00Z')},
}
results=[]
for name,settings in cases.items():
 target=out/f'{name}.rgba16f'
 query={'dayNight':1,'latitude':40.7128,'longitude':-74.006,'timeZone':'America/New_York','fixedDt':0,'dumpClouds':1,'dump':target,**settings}
 process=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in query.items())],capture_output=True,text=True,timeout=90)
 (out/f'{name}.log').write_text(process.stdout+process.stderr)
 assert process.returncode==0,process.stdout+process.stderr
 d=json.loads(next(line.removeprefix('Ocean diagnostics: ') for line in process.stdout.splitlines() if line.startswith('Ocean diagnostics: ')))
 assert d['offscreen'] and d['windowCount']==0 and d['activationPolicy']==2 and not d['errors']
 expected=name not in ['fixed_reference','missing_location']
 assert d['dayNightActive']==expected and d['solarCalculations']==int(expected) and d['solarCacheWrites']==0
 allocated=settings.get('dayNight',1)!=0
 assert d['galaxyAtlasWidth']==(2048 if allocated else 1) and d['starAtlasWidth']==(1024 if allocated else 1) and d['starCount']==(12000 if allocated else 0)
 sun_visibility=struct.unpack('<f',Path(str(target)+'.clouds').read_bytes()[-4:])[0]
 assert 0<=sun_visibility<=1
 results.append({'case':name,'settings':settings,'diagnostics':d})
 print(f'PASS: {name}, sun altitude {d["sunAltitude"]:.2f}°, zero windows / cache writes',flush=True)
report={'passed':True,'cases':results,'scope':'Synthetic public coordinates only. No network requests, OS location access, windows or user cache writes. All sky/environment/sun readbacks checked; visual fixtures need review.'}
(out/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
