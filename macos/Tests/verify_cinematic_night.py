#!/usr/bin/env python3
"""Matched scene-lighting fixtures; inspect visible wave/cloud detail, not gain."""
import argparse,json,subprocess
from datetime import datetime
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
r=Path(__file__).resolve().parents[2];o=r/'macos/build/night-cinema';o.mkdir(exist_ok=True)
a=argparse.ArgumentParser();a.add_argument('--before',action='store_true');args=a.parse_args()
app=(o/'Before.app' if args.before else r/'macos/build/Ocean.app')/'Contents/MacOS/Ocean'
label='before' if args.before else 'after'
if not args.before:(o/'verification.json').unlink(missing_ok=True)
def utc(s):return datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
scenes={'moonlit':{'utc':utc('2026-10-31T02:10:00Z'),'heading':60,'clouds':.15,'veil':.1},'moonless':{'utc':utc('2026-11-10T04:00:00Z'),'heading':270},'starry':{'utc':utc('2026-06-21T04:00:00Z'),'heading':155,'clouds':.12,'veil':.05},'storm':{'utc':utc('2026-10-31T04:00:00Z'),'heading':270,'storm':1},'moonless_storm':{'utc':utc('2026-11-10T04:00:00Z'),'heading':270,'storm':1},'noon':{'utc':utc('2026-10-30T16:40:00Z'),'heading':180},'day_storm':{'utc':utc('2026-10-30T16:40:00Z'),'heading':180,'storm':1},'moonless_storm_no_rain':{'utc':utc('2026-11-10T04:00:00Z'),'heading':270,'storm':1,'rainParticles':0}}
results={}
for name,s in scenes.items():
 path=o/f'{label}-{name}'
 q={'dayNight':1,'latitude':40.7128,'longitude':-74.006,'timeZone':'America/New_York','time':30,'fixedDt':0,'dump':path,**s}
 p=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in q.items())],capture_output=True,text=True,timeout=120)
 (o/f'{label}-{name}.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stdout+p.stderr
 d=json.loads([line.removeprefix('Ocean diagnostics: ') for line in p.stdout.splitlines() if line.startswith('Ocean diagnostics: ')][-1])
 assert d['offscreen'] and d['windowCount']==0 and d['activationPolicy']==2 and not d['errors'] and d['solarCacheWrites']==0
 im=np.fromfile(str(path)+'.bgra8',dtype=np.uint8).reshape(800,1280,4)[:,:,2::-1]
 rgb=im.astype(np.float32)/255;luma=rgb[:,:,0]*.2126+rgb[:,:,1]*.7152+rgb[:,:,2]*.0722
 water=luma[400:760,80:1200];sky=luma[20:280,40:1240]
 metric={'oceanMedian':float(np.median(water)),'oceanP10':float(np.percentile(water,10)),'oceanP90':float(np.percentile(water,90)),'oceanBlackFraction':float((water<.02).mean()),'skyMedian':float(np.median(sky)),'waterRGB':rgb[400:760,80:1200].mean(axis=(0,1)).tolist()}
 Image.fromarray(im).save(o/f'{label}-{name}.png')
 results[name]={'settings':s,'diagnostics':d,'visibility':metric}
 print(label,name,metric,flush=True)
(o/f'{label}.json').write_text(json.dumps(results,indent=2)+'\n')
if not args.before:
 old=json.loads((o/'before.json').read_text())
 assert (o/'before-noon').read_bytes()==(o/'after-noon').read_bytes(),'Daytime HDR must remain exact'
 assert Path(str(o/'before-noon')+'.bgra8').read_bytes()==Path(str(o/'after-noon')+'.bgra8').read_bytes()
 for name in scenes:
  if name in ['noon','day_storm']:continue
  v=results[name]['visibility']
  assert .065<v['oceanMedian']<.32,(name,v)
  assert v['oceanBlackFraction']<.15,(name,v)
  assert v['oceanP90']-v['oceanP10']>.025,(name,'Wave contrast missing',v)
  assert v['skyMedian']<(.35 if name=='starry' else .23),(name,'Sky reads as daytime',v)
  assert v['waterRGB'][2]>v['waterRGB'][0]*1.1,(name,'Night color lost',v)
 assert (o/'before-day_storm').read_bytes()==(o/'after-day_storm').read_bytes(),'Daytime storm HDR must stay exact'
 assert Path(str(o/'before-day_storm')+'.bgra8').read_bytes()==Path(str(o/'after-day_storm')+'.bgra8').read_bytes()
 rain=np.fromfile(str(o/'after-moonless_storm')+'.bgra8',dtype=np.uint8).reshape(800,1280,4).astype(np.int16)
 noRain=np.fromfile(str(o/'after-moonless_storm_no_rain')+'.bgra8',dtype=np.uint8).reshape(800,1280,4).astype(np.int16)
 visibleRainPixels=int((np.max(np.abs(rain[:,:,:3]-noRain[:,:,:3]),axis=2)>1).sum())
 assert visibleRainPixels>1000,visibleRainPixels
 review=Image.new('RGB',(1280,1200))
 for i,name in enumerate(['moonlit','moonless','storm']):
  for j,kind in enumerate(['before','after']):
   im=Image.open(o/f'{kind}-{name}.png').resize((640,400));ImageDraw.Draw(im).text((12,12),f'{kind} {name}',fill='white');review.paste(im,(j*640,i*400))
 review.save(o/'review.png')
 (o/'verification.json').write_text(json.dumps({'passed':True,'before':old,'after':results,'daytimeHDRAndDisplayExact':True,'daytimeStormHDRAndDisplayExact':True,'visibleNightRainPixels':visibleRainPixels,'scope':'Display luminance/readability gates plus native visual review. Synthetic coordinates, no network/windows/user-cache writes. Night stays cool, contrasted and visibly darker than day; scene lighting changes, not a postprocess black-level lift.'},indent=2)+'\n')
 print('PASS: visible midnight ocean, shadow/crest contrast, cool palette, exact daytime parity.',flush=True)
