#!/usr/bin/env python3
"""Hold lighting independently of animated water; default automatic still advances."""
import json,os,subprocess
from pathlib import Path
import numpy as np
root=Path(__file__).resolve().parents[2];out=root/'macos/build/daylight-time';out.mkdir(exist_ok=True)
report=out/'verification.json';report.unlink(missing_ok=True)
app=root/'macos/build/Ocean.app/Contents/MacOS/Ocean';results={}
env=os.environ.copy();env.update(MTL_DEBUG_LAYER='1',MTL_SHADER_VALIDATION='1')
for name,mode,frame in [('sunset_before','sunset',8),('sunset_after','sunset',188),('auto_before','automatic',8),('auto_after','automatic',188),('custom','18:30',8),('midnight','midnight',8)]:
 target=out/name
 q={'dayNight':1,'latitude':40.7128,'longitude':-74.006,'timeZone':'America/New_York','utc':1793378400,
    'fixedDt':1/30,'cycleRate':300,'verifyFrame':frame,'daylightTime':mode,'dump':target}
 p=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in q.items())],env=env,capture_output=True,text=True,timeout=150)
 (out/f'{name}.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stdout+p.stderr
 d=json.loads([s.removeprefix('Ocean diagnostics: ') for s in p.stdout.splitlines() if s.startswith('Ocean diagnostics: ')][-1])
 assert d['offscreen'] and d['windowCount']==0 and d['errors']==[] and d['solarCacheWrites']==0
 assert d['daylightTime']==mode and d['daylightHeld']==(mode!='automatic')
 assert 1<=d['solarCalculations']<=2
 assert np.isfinite(np.fromfile(target,dtype='<f2')).all()
 results[name]={'lightingUTC':d['lightingUTC'],'sunAltitude':d['sunAltitude'],'elapsed':d['elapsed'],'solarCalculations':d['solarCalculations'],'daylightHeld':d['daylightHeld']}
 print('PASS',name,json.dumps(results[name]),flush=True)
assert results['sunset_before']['lightingUTC']==results['sunset_after']['lightingUTC']
assert results['sunset_before']['sunAltitude']==results['sunset_after']['sunAltitude']
assert abs(results['sunset_after']['sunAltitude']+.833)<.02,'Sunset must use cached local sunset'
assert results['auto_after']['lightingUTC']-results['auto_before']['lightingUTC']>1799,'Automatic must resume the live clock'
a=np.fromfile(out/'sunset_before.bgra8',dtype=np.uint8).reshape(800,1280,4).astype(np.int16)
b=np.fromfile(out/'sunset_after.bgra8',dtype=np.uint8).reshape(800,1280,4).astype(np.int16)
moving=int((np.abs(a[400:,:,:3]-b[400:,:,:3]).max(axis=2)>3).sum())
assert moving>1000,'Holding daylight must not pause the waves'
from datetime import datetime
from zoneinfo import ZoneInfo
clock=datetime.fromtimestamp(results['custom']['lightingUTC'],ZoneInfo('America/New_York'))
assert (clock.hour,clock.minute)==(18,30)
report.write_text(json.dumps({'passed':True,'cases':results,'animatedWaterPixels':moving,'scope':'Six actual Metal fixtures: held sunset/custom/midnight, independent animated water, advancing automatic clock, finite HDR and bounded daily calculations. No windows, providers, user preference reads or cache writes.'},indent=2)+'\n')
print('PASS: held lighting, animated water, custom local time and automatic clock')
