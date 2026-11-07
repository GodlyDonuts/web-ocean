#!/usr/bin/env python3
"""Matched night lighting readbacks and daytime parity against a saved app.

Run --before before editing, then run without it after rebuilding. All captures
are windowless with fixed coordinates/time; no provider calls or cache writes.
"""
import argparse,json,subprocess
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw

root=Path(__file__).resolve().parents[2]
out=root/'macos/build/night-silver';out.mkdir(exist_ok=True,parents=True)
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--before',action='store_true');args=p.parse_args()
label='before' if args.before else 'after'
app=(out/'Before.app' if args.before else root/'macos/build/Ocean.app')/'Contents/MacOS/Ocean'
scenes={
 'moonlit':{'utc':1793415600,'heading':67.8,'clouds':.12,'veil':.03},
 'moonrise':{'utc':1793412600,'heading':60,'clouds':.15,'veil':.1},
 'moonlit_clouds':{'utc':1793412600,'heading':60,'clouds':.4,'veil':.1},
 'starry':{'utc':1782014400,'heading':155,'clouds':.12,'veil':.05},
 'moonless':{'utc':1794283200,'heading':270},
 'storm':{'utc':1794283200,'heading':270,'storm':1,'time':60},
 'noon':{'utc':1793378400,'heading':180},
 'day_storm':{'utc':1793378400,'heading':180,'storm':1}}
results={}
for name,settings in scenes.items():
 target=out/f'{label}-{name}'
 q={'dayNight':1,'latitude':40.7128,'longitude':-74.006,'timeZone':'America/New_York','time':30,'fixedDt':0,'dump':target,**settings}
 run=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in q.items())],capture_output=True,text=True,timeout=150)
 (out/f'{label}-{name}.log').write_text(run.stdout+run.stderr)
 assert run.returncode==0,run.stdout+run.stderr
 d=json.loads(next(s.removeprefix('Ocean diagnostics: ') for s in run.stdout.splitlines() if s.startswith('Ocean diagnostics: ')))
 assert d['offscreen'] and d['windowCount']==0 and d['activationPolicy']==2 and not d['errors'] and d['solarCacheWrites']==0
 w,h=d['width'],d['height']
 hdr=np.fromfile(target,dtype='<f2').reshape(h,w,4).astype(np.float32)
 assert np.isfinite(hdr).all() and hdr[:,:,:3].min()>=0,(name,'Invalid HDR')
 im=Image.frombytes('RGBA',(w,h),Path(str(target)+'.bgra8').read_bytes(),'raw','BGRA').convert('RGB')
 im.save(out/f'{label}-{name}.png')
 rgb=np.asarray(im).astype(np.float32)/255
 water=rgb[int(h*.56):int(h*.94),int(w*.08):int(w*.92)]
 luma=water@np.array([.2126,.7152,.0722])
 metrics={'waterP10':float(np.percentile(luma,10)),'waterMedian':float(np.median(luma)),
  'waterP95':float(np.percentile(luma,95)),'waterP99':float(np.percentile(luma,99)),
  'waterBlackFraction':float((luma<.01).mean()),'waterMeanRGB':water.mean(axis=(0,1)).tolist()}
 results[name]={'settings':settings,'metrics':metrics,'errors':d['errors'],'windowCount':d['windowCount']}
 print(label,name,json.dumps(metrics),flush=True)
(out/f'{label}.json').write_text(json.dumps(results,indent=2)+'\n')
if not args.before:
 before=json.loads((out/'before.json').read_text())
 for name in ['noon','day_storm']:
  for suffix in ['', '.bgra8']:
   assert Path(str(out/f'before-{name}')+suffix).read_bytes()==Path(str(out/f'after-{name}')+suffix).read_bytes(),(name,'Daytime changed')
 for name in ['moonlit','moonrise','moonlit_clouds','starry','moonless','storm']:
  v=results[name]['metrics']
  assert v['waterP95']-v['waterP10']>.025,(name,'Water detail lost')
  assert v['waterBlackFraction']<.15,(name,'Water crushed to black')
 old=before['moonlit']['metrics'];new=results['moonlit']['metrics']
 assert new['waterP99']/new['waterMedian']>old['waterP99']/old['waterMedian'], 'Moonlit highlight contrast must improve'
 sheet=Image.new('RGB',(1280,400*6))
 for row,name in enumerate(['moonlit','moonrise','moonlit_clouds','starry','moonless','storm']):
  for col,version in enumerate(['before','after']):
   im=Image.open(out/f'{version}-{name}.png').resize((640,400));ImageDraw.Draw(im).text((12,12),f'{version}: {name}',fill='white');sheet.paste(im,(col*640,row*400))
 sheet.save(out/'comparison.png')
 (out/'verification.json').write_text(json.dumps({'passed':True,'before':before,'after':results,'daytimeHDRAndDisplayExact':True,'scope':'Finite HDR, readable water, stronger moonlit highlight contrast and exact daytime parity. Display luma proxies do not prove realism; inspect native captures. Eight fixed scenes, zero windows/providers/cache writes.'},indent=2)+'\n')
 print('PASS: silver night readbacks, moonlit contrast and exact daylight/storm parity',flush=True)
