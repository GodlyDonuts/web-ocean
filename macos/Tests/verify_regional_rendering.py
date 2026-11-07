#!/usr/bin/env python3
"""Actual GPU visible-region / full-reveal parity, including broad bloom."""
import json,os,subprocess
from pathlib import Path
import numpy as np
root=Path(__file__).resolve().parents[2];out=root/'macos/build/regional';out.mkdir(exist_ok=True)
app=root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
env=os.environ.copy();env.update(MTL_DEBUG_LAYER='1',MTL_SHADER_VALIDATION='1')
scenes={'day':{'sunElev':12,'sunAzim':-18},'night':{'dayNight':1,'latitude':40.7128,'longitude':-74.006,'timeZone':'America/New_York','utc':1793412600},'storm':{'storm':1,'dayNight':1,'latitude':40.7128,'longitude':-74.006,'timeZone':'America/New_York','utc':1794283200}}
results=[]
def run(name,q):
 target=out/name
 query={'time':40,'fixedDt':1/30,'dump':target,**q}
 p=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in query.items())],capture_output=True,text=True,env=env,timeout=180)
 (out/f'{name}.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stdout+p.stderr
 d=json.loads(next(x.removeprefix('Ocean diagnostics: ') for x in p.stdout.splitlines() if x.startswith('Ocean diagnostics: ')))
 assert not d['errors'] and d['windowCount']==0 and d['solarCacheWrites']==0
 w,h=d['width'],d['height'];hdr=np.fromfile(target,dtype='<f2').reshape(h,w,4);display=np.fromfile(str(target)+'.bgra8',dtype='u1').reshape(h,w,4)
 assert np.isfinite(hdr).all()
 return hdr,display,d
for scene,settings in scenes.items():
 ref,ref_display,_=run(scene+'-full',settings)
 tile_hdr,tile_display,_=run(scene+'-tiles',{**settings,'testTiles':1})
 assert _['tilePresentationVerified'],'Four GPU tile crops must reconstruct the same-frame source byte-for-byte'
 for name,region in [('left',(0,0,.05,1)),('right',(.95,0,.05,1)),('top',(0,0,1,.05)),('bottom',(0,.95,1,.05)),('center',(.4,.4,.1,.1)),('reveal',(0,0,.05,1)),('move',(.95,0,.05,1))]:
  q={**settings,'visibleRegion':','.join(map(str,region))}
  if name=='reveal':q['revealFrame']=8
  if name=='move':q.update(visibleRegion='0,0,0.05,1',visibleRegionAfter='0.95,0,0.05,1',regionChangeFrame=5)
  hdr,display,d=run(scene+'-'+name,q)
  h,w=hdr.shape[:2];x,y,rw,rh=region
  ys=slice(int(np.ceil(y*h)),int(np.floor((y+rh)*h)));xs=slice(int(np.ceil(x*w)),int(np.floor((x+rw)*w)))
  if name=='reveal':ys=xs=slice(None)
  hd=float(np.abs(hdr[ys,xs].astype('f4')-ref[ys,xs].astype('f4')).max())
  dd=int(np.abs(display[ys,xs].astype('i2')-ref_display[ys,xs].astype('i2')).max())
  assert hd==0,(scene,name,'visible HDR changed',hd)
  assert dd<=1,(scene,name,'visible bloom/composite changed',dd)
  results.append({'scene':scene,'region':name,'shadedFraction':d['shadedFraction'],'maxHDRDifference':hd,'maxDisplayLSB':dd})
  print('PASS',results[-1],flush=True)
for w,h in [(1279,799),(1400,400),(400,1200)]:
 ref,rd,_=run(f'size-{w}-{h}-full',{'renderWidth':w,'renderHeight':h})
 hdr,display,d=run(f'size-{w}-{h}-crop',{'renderWidth':w,'renderHeight':h,'visibleRegion':'0,0,0.05,1'})
 columns=max(1,int(hdr.shape[1]*.05))
 assert np.array_equal(hdr[:,:columns],ref[:,:columns])
 assert np.array_equal(display[:,:columns],rd[:,:columns])
 results.append({'extent':[w,h],'region':'left','shadedFraction':d['shadedFraction'],'maxHDRDifference':0,'maxDisplayLSB':0})
# The snapshot readback must match the normal full composite, not contain a
# cropped/stale hidden region, including non-256-aligned pixel row widths.
raw=out/'snapshot.bgra8'
_,display,_=run('snapshot',{'snapshotPath':raw,'renderWidth':1279,'renderHeight':799,'visibleRegion':'0,0,0.05,1'})
assert raw.stat().st_size==display.size
# snapshotPath requests a full snapshot on frame 8, so every pixel must match.
assert np.array_equal(np.fromfile(raw,dtype='u1'),display.reshape(-1))
(out/'verification.json').write_text(json.dumps({'passed':True,'cases':results,'snapshotReadback':True,'tileReconstruction':{'scenes':list(scenes),'sameFrameByteExact':True},'scope':'Metal validation, zero windows; visible HDR exact, display <=1 LSB, full reveal and snapshot. OS visibility separately requires interactive validation.'},indent=2)+'\n')
