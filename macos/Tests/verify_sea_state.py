#!/usr/bin/env python3
"""Read real GPU wave fields: offshore swell, wind growth, rain independence."""
import json, math, struct, subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[2]
out=root/'macos/build/sea-state';out.mkdir(parents=True,exist_ok=True)
report=out/'verification.json';report.unlink(missing_ok=True)
app=root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
cases={
 'light_wind':{'weatherValues':'0,0.4,2.75,171,0,0'},
 'heavy_rain_light_wind':{'weatherValues':'1,1,2.75,171,1,0.8'},
 'breeze':{'weatherValues':'0,0.4,7,118,0,0'},
 'strong_wind':{'weatherValues':'0,0.4,15,118,0,0'},
 'gale':{'weatherValues':'0,0.4,30,118,0,0'},
 'extreme_wind':{'weatherValues':'0,0.4,45,118,0,0'},
 'light_wind_t10':{'weatherValues':'0,0.4,2.75,171,0,0','time':10},
 'light_wind_t60':{'weatherValues':'0,0.4,2.75,171,0,0','time':60},
 'light_wind_t120':{'weatherValues':'0,0.4,2.75,171,0,0','time':120},
 'light_wind_without_swell':{'weatherValues':'0,0.4,2.75,171,0,0','swellHs':0},
}
results={};fields={}
for name,settings in cases.items():
 path=out/name
 q={'fixedDt':0,'sunElev':20,'time':30,'renderWidth':640,'renderHeight':400,'dumpMips':1,'dump':path,**settings}
 p=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in q.items())],capture_output=True,text=True,timeout=120)
 (out/f'{name}.log').write_text(p.stdout+p.stderr)
 assert p.returncode==0,p.stdout+p.stderr
 d=json.loads([s.removeprefix('Ocean diagnostics: ') for s in p.stdout.splitlines() if s.startswith('Ocean diagnostics: ')][-1])
 assert not d['errors'] and d['offscreen'] and d['windowCount']==0 and d['solarCacheWrites']==0
 with Path(str(path)+'.mips').open('rb') as f: raw=f.read(6*256*256*8)
 assert len(raw)==6*256*256*8
 variance=0
 for band in range(6):
  heights=[v[1] for v in struct.iter_unpack('<eeee',raw[band*65536*8:(band+1)*65536*8])]
  assert all(math.isfinite(v) for v in heights)
  mean=sum(heights)/len(heights)
  variance+=sum((v-mean)**2 for v in heights)/len(heights)
 hs=4*math.sqrt(variance)
 results[name]={'heightProxyMeters':hs,'windMps':d['weatherWind'] if d['weatherActive'] else settings.get('windSpeed'), 'errors':d['errors']}
 if name in ['light_wind','heavy_rain_light_wind']:fields[name]=raw
 print(f'PASS: {name}, spectral Hs proxy {hs:.3f} m',flush=True)
# This regression fails when precipitation changes swell energy or reseeds waves.
assert fields['light_wind']==fields['heavy_rain_light_wind'],'Rain alone changed the wave displacement field'
for key in ['light_wind','light_wind_t10','light_wind_t60','light_wind_t120']:
 assert 0.8<results[key]['heightProxyMeters']<3,'Background swell must remain bounded in light local wind'
assert results['light_wind_without_swell']['heightProxyMeters']<results['light_wind']['heightProxyMeters']*0.5
order=['light_wind','breeze','strong_wind','gale','extreme_wind']
assert all(results[a]['heightProxyMeters']<results[b]['heightProxyMeters'] for a,b in zip(order,order[1:]))
assert 5<results['extreme_wind']['heightProxyMeters']<14
report.write_text(json.dumps({'passed':True,'cases':results,'rainOnlyDisplacementByteExact':True,'scope':'Real GPU fields at fixed wave time. Height proxy is 4*sqrt(sum of six cascade elevation variances), not observed local marine conditions or the maximum individual wave. No windows, forecast calls, location prompts or user cache writes.'},indent=2)+'\n')
print('PASS: independent offshore swell, wind-driven height growth and exact rain-only displacement invariance')
