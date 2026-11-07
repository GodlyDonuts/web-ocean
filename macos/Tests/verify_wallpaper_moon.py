#!/usr/bin/env python3
"""Read actual default-path lunar disks/phases and accelerated fixed-view motion."""
import json,math,os,subprocess
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2];out=root/'macos/build/moon-arc';out.mkdir(exist_ok=True)
report=out/'verification.json';report.unlink(missing_ok=True)
fixtures=json.loads((root/'macos/build/unit/wallpaper-moon.json').read_text());assert fixtures['passed']
app=root/'macos/build/Ocean.app/Contents/MacOS/Ocean';results=[]
pitch=math.radians(-5.5);forward=np.array([0,math.sin(pitch),-math.cos(pitch)]);up=np.array([0,math.cos(pitch),math.sin(pitch)])
def project(v):
 depth=v@forward
 return np.array([(v[0]/(depth*math.tan(math.radians(29))*1.6)+1)*640,(1-v@up/(depth*math.tan(math.radians(29))))*400])
env=os.environ.copy();env.update(MTL_DEBUG_LAYER='1',MTL_SHADER_VALIDATION='1')
for f in fixtures['fixtures']:
 name=f['name'];target=out/name;arc=name.startswith('arc_')
 q={'dayNight':1,'latitude':40.7128,'longitude':-74.006,'timeZone':'America/New_York','utc':1793404800 if arc else f['utc'],
    'fixedDt':1/30 if arc else 0,'cycleRate':300 if arc else 1,'verifyFrame':188 if name=='arc_after' else 8,
    'heading':270,'clouds':0,'veil':0,'dump':target}
 p=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in q.items())],env=env,capture_output=True,text=True,timeout=150)
 (out/f'{name}.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stdout+p.stderr
 d=json.loads([s.removeprefix('Ocean diagnostics: ') for s in p.stdout.splitlines() if s.startswith('Ocean diagnostics: ')][-1])
 assert d['offscreen'] and d['windowCount']==0 and not d['errors'] and d['solarCacheWrites']==0 and d['solarCalculations']<=2
 if arc:assert abs(q['utc']+d['cachedSkyElapsed']*300-f['utc'])<.01
 hdr=np.fromfile(target,dtype='<f2').reshape(800,1280,4).astype(np.float32);assert np.isfinite(hdr).all()
 im=Image.frombytes('RGBA',(1280,800),Path(str(target)+'.bgra8').read_bytes(),'raw','BGRA').convert('RGB');im.save(out/f'{name}.png')
 center=project(np.array(f['direction']));px,py=center
 yy,xx=np.mgrid[int(py)-10:int(py)+11,int(px)-10:int(px)+11];radius=np.hypot(xx+.5-px,yy+.5-py)
 luma=hdr[yy,xx,:3]@np.array([.2126,.7152,.0722]);background=float(np.median(luma[(radius>=7)&(radius<=10)]))
 weights=np.maximum(0,luma-background)*(radius<=5);energy=float(weights.sum());peak=float(weights.max())
 metric={'name':name,'illuminatedFraction':f['illuminatedFraction'],'expectedPixel':center.tolist(),'diskEnergyAboveBackground':energy,'peak':peak,'errors':d['errors']}
 if name!='new':
  assert peak>.01 and energy>.02,(name,'Missing lunar disk',metric)
  measured=np.array([((xx+.5)*weights).sum()/energy,((yy+.5)*weights).sum()/energy])
  assert np.linalg.norm(measured-center)<3,(name,'Moon left intended path',measured,center)
  metric['measuredPixel']=measured.tolist()
 results.append(metric);print('PASS',name,json.dumps(metric),flush=True)
full=next(x for x in results if x['name']=='full');new=next(x for x in results if x['name']=='new')
assert new['diskEnergyAboveBackground']<full['diskEnergyAboveBackground']*.15,'New Moon must not emit a full disk'
for name in ['waxing_quarter','waning_quarter']:
 quarter=next(x for x in results if x['name']==name)
 assert .08<quarter['diskEnergyAboveBackground']/full['diskEnergyAboveBackground']<.8,(name,'Quarter rendered as full or new')
 limbOffset=quarter['measuredPixel'][0]-quarter['expectedPixel'][0]
 assert limbOffset>.3 if name=='waxing_quarter' else limbOffset<-.3,(name,'Waxing/waning bright side reversed')
a,b=[x for x in results if x['name'].startswith('arc_')]
assert np.linalg.norm(np.array(b['measuredPixel'])-a['measuredPixel'])>20,'Default Moon must move across the fixed view'
sheet=Image.new('RGB',(1280,800))
for i,name in enumerate(['waxing_quarter','full','waning_quarter','arc_after']):
 im=Image.open(out/f'{name}.png').resize((640,400));ImageDraw.Draw(im).text((12,12),name,fill='white');sheet.paste(im,((i%2)*640,(i//2)*400))
sheet.save(out/'review.png')
report.write_text(json.dumps({'passed':True,'cases':results,'scope':'Actual Metal default-path disks, phase-dependent radiance and accelerated 30-minute motion from one UTC anchor and fixed camera. Metal validation enabled. CPU tests separately verify exact phase fraction/bright-limb orientation, whole-night framing and cached rise/set bounds. Zero windows, providers or user-cache writes.'},indent=2)+'\n')
print('PASS: default visible Moon arc and new/quarter/full lunar disk readbacks')
