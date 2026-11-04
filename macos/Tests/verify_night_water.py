#!/usr/bin/env python3
"""Native storm-wave, underwater-view and night-foam regression captures."""
import json,os,struct,subprocess
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2];out=root/'macos/build/night-water-fix';out.mkdir(exist_ok=True)
app=root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
report=out/'verification.json';report.unlink(missing_ok=True)
results={}
def run(name,settings):
 q={'dayNight':1,'latitude':40.7128,'longitude':-74.006,'timeZone':'America/New_York','utc':1794283200,'heading':270,'storm':1,'rainParticles':0,'time':30,'fixedDt':0,'renderWidth':960,'renderHeight':600,'dumpWater':1,'dump':out/name,**settings}
 env=os.environ.copy();env.update(MTL_DEBUG_LAYER='1',MTL_SHADER_VALIDATION='1')
 p=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in q.items())],capture_output=True,text=True,env=env,timeout=150)
 (out/f'{name}.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stdout+p.stderr
 d=json.loads(next(x.removeprefix('Ocean diagnostics: ') for x in p.stdout.splitlines() if x.startswith('Ocean diagnostics: ')))
 assert not d['errors'] and d['windowCount']==0 and d['activationPolicy']==2 and d['solarCacheWrites']==0
 w,h=d['width'],d['height'];im=Image.frombytes('RGBA',(w,h),(out/f'{name}.bgra8').read_bytes(),'raw','BGRA').convert('RGB');im.save(out/f'{name}.png')
 hdr=np.fromfile(out/name,dtype='<f2').astype(np.float32).reshape(h,w,4)
 assert np.isfinite(hdr).all()
 water=struct.unpack('<4f',(out/f'{name}.water').read_bytes());assert np.isfinite(water).all() and 0<=water[2]<=1
 black=float((hdr[int(h*.6):,:,:3].max(axis=2)<.00001).mean())
 if settings.get('dbg',0)!=9:assert black<.001,(name,'unrendered black water',black)
 results[name]={'settings':settings,'diagnostics':d,'cameraWaterHeightDepthBlend':water[:3],'lowerViewBlackFraction':black}
 print('PASS',name,'camera depth',round(water[1],3),'black fraction',black,flush=True)
 return hdr
for t in [10,30,60,90,120,150]:run(f'after-{t}',{'time':t})
mask=run('surface-mask',{'time':60,'dbg':9})
above=(mask[:,:,0]>.99)&(mask[:,:,3]>.99);assert above.sum()>1000,'Fixture must show waves above eye level'
foam=mask[:,:,1]>.5;assert foam.sum()>100,'Fixture must contain foam'
image=np.fromfile(out/'after-60',dtype='<f2').astype(np.float32).reshape(600,960,4)
assert np.median(image[:,:,:3][above].max(axis=1))>.0005,'Raised wave faces must retain illumination'
for name,s in [('rain',{'time':60,'rainParticles':1}),('day',{'utc':1793378400}),('clear',{'storm':0,'clouds':0,'veil':0}),('portrait',{'renderWidth':600,'renderHeight':960,'time':60}),('submerged',{'time':60,'testEyeHeight':.25}),('submerged-day',{'time':60,'testEyeHeight':.25,'utc':1793378400})]:run(name,s)
assert any(x['cameraWaterHeightDepthBlend'][2]>.9 for x in results.values()),'Fixtures must include actual camera submersion'
# Historical comparison is optional: clean clones have no local before captures.
comparison_available=all((out/f'before-{t}.png').exists() for t in [60,90])
if comparison_available:
 review=Image.new('RGB',(1920,1200))
 for row,t in enumerate([60,90]):
  for col,label in enumerate(['before','after']):
   im=Image.open(out/f'{label}-{t}.png');ImageDraw.Draw(im).text((10,10),f'{label}: storm at {t}s',fill='white');review.paste(im,(col*960,row*600))
 review.save(out/'review.png')
report.write_text(json.dumps({'passed':True,'historicalComparisonAvailable':comparison_available,'aboveEyeSurfacePixels':int(above.sum()),'foamPixels':int(foam.sum()),'cases':results,'scope':'Actual Metal geometry and camera height-field sampling; API/shader validation enabled. Includes a synthetic low-eye-height submersion fixture, raised crests, foam, rain, daylight, clear and portrait views. No windows, network, location prompts or user-cache writes.'},indent=2)+'\n')
