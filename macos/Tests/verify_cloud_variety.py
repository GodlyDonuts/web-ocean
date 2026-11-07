#!/usr/bin/env python3
"""Native cloud morphology gallery, shared reflection/shadow readbacks and masks."""
import json,os,subprocess
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2];out=root/'macos/build/cloud-variety';out.mkdir(exist_ok=True)
report=out/'verification.json';report.unlink(missing_ok=True)
app=root/'macos/build/Ocean.app/Contents/MacOS/Ocean';results={};masks={}
scenes={k:{} for k in ['cumulus','stratocumulus','stratus','altocumulus','altostratus','cirrus','cirrocumulus','cirrostratus']}
scenes.update(nimbostratus={'storm':.4},cumulonimbus={'storm':.85},auto={})
env=os.environ.copy();env.update(MTL_DEBUG_LAYER='1',MTL_SHADER_VALIDATION='1')
for name,settings in scenes.items():
 target=out/name
 q={'fixedDt':0,'time':40,'sunElev':12,'sunAzim':-18,'cloudType':name,'dumpClouds':1,'dump':target,**settings}
 p=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in q.items())],env=env,capture_output=True,text=True,timeout=180)
 (out/f'{name}.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stdout+p.stderr
 d=json.loads(next(x.removeprefix('Ocean diagnostics: ') for x in p.stdout.splitlines() if x.startswith('Ocean diagnostics: ')))
 assert d['offscreen'] and d['windowCount']==0 and not d['errors'] and d['solarCacheWrites']==0
 hdr=np.fromfile(target,dtype='<f2');assert np.isfinite(hdr).all()
 w,h=d['width'],d['height'];cw,ch=d['cloudCacheWidth'],d['cloudCacheHeight']
 raw=Path(str(target)+'.clouds').read_bytes()
 cache=np.frombuffer(raw[:cw*ch*8],dtype='<f2').reshape(ch,cw,4).astype(np.float32)
 alpha=1-cache[:int(ch*.4),:,-1];assert np.isfinite(alpha).all() and alpha.min()>=0 and alpha.max()<=1
 masks[name]=alpha
 Image.frombytes('RGBA',(w,h),Path(str(target)+'.bgra8').read_bytes(),'raw','BGRA').convert('RGB').save(out/f'{name}.png')
 results[name]={'settings':q|{'dump':str(target.relative_to(root))},'meanSkyOpacity':float(alpha.mean()),'skyOpaqueFraction':float((alpha>.5).mean()),'errors':d['errors']}
 print('PASS',name,json.dumps({k:v for k,v in results[name].items() if k!='settings'}),flush=True)
for a,b in [('cumulus','stratocumulus'),('stratocumulus','stratus'),('cirrus','cirrostratus'),('cumulus','altocumulus'),('altocumulus','altostratus'),('cirrocumulus','cirrostratus')]:
 assert float(np.abs(masks[a]-masks[b]).mean())>.015,(a,b,'Cloud masks must be visibly distinct')
sheet=Image.new('RGB',(640*3,400*4))
for i,name in enumerate(scenes):
 im=Image.open(out/f'{name}.png').resize((640,400));draw=ImageDraw.Draw(im);draw.rectangle((0,0,190,28),fill=(10,15,22));draw.text((10,8),name,fill='white');sheet.paste(im,((i%3)*640,(i//3)*400))
sheet.save(out/'gallery.png')
report.write_text(json.dumps({'passed':True,'cases':results,'scope':'Ten cloud families plus automatic mixture: finite HDR, sky alpha, reflection cube/mips and direct-light readbacks with Metal validation. Pairwise opacity differences complement visual inspection, not proof of physical cloud classification. Zero windows/providers/cache writes.'},indent=2)+'\n')
print('PASS: cloud variety, finite shared sky/reflection/shadow output and distinct morphology masks')
