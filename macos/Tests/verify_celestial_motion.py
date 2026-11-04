#!/usr/bin/env python3
"""Verify actual GPU sun/Moon disk movement with a fixed camera per pair."""
import json,math,statistics,struct,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[2]
out=root/'macos/build/celestial-motion';out.mkdir(exist_ok=True)
(out/'verification.json').unlink(missing_ok=True)
trajectory=json.loads((out/'trajectory.json').read_text());assert trajectory['passed']
app=root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
results=[]
for fixture in trajectory['fixtures']:
 name=fixture['name'];target=out/f'{name}.rgba16f'
 query={'dayNight':1,'latitude':40.7128,'longitude':-74.006,'timeZone':'America/New_York','fixedDt':1/30,'cycleRate':300,'verifyFrame':fixture['verifyFrame'],'clouds':0,'veil':0,'renderWidth':1280,'renderHeight':800,'utc':fixture['anchorUTC'],'heading':fixture['heading'],'dump':target}
 p=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in query.items())],capture_output=True,text=True,timeout=90)
 (out/f'{name}.log').write_text(p.stdout+p.stderr)
 assert p.returncode==0,p.stdout+p.stderr
 d=json.loads([line.removeprefix('Ocean diagnostics: ') for line in p.stdout.splitlines() if line.startswith('Ocean diagnostics: ')][-1])
 assert d['offscreen'] and d['windowCount']==0 and d['activationPolicy']==2 and d['dayNightActive'] and not d['errors']
 assert abs(fixture['anchorUTC']+d['cachedSkyElapsed']*300-fixture['utc'])<0.01
 data=target.read_bytes();width=d['width'];height=d['height'];assert(width,height)==(1280,800)
 px,py=fixture['pixel']
 def luminance(x,y):
  r,g,b,_=struct.unpack_from('<eeee',data,(y*width+x)*8)
  return r*.2126+g*.7152+b*.0722
 annulus=[];pixels=[]
 for y in range(int(py)-10,int(py)+11):
  for x in range(int(px)-10,int(px)+11):
   radius=math.hypot(x+.5-px,y+.5-py)
   if 6<=radius<=10:annulus.append(luminance(x,y))
   if radius<=4.5:pixels.append((x+.5,y+.5,luminance(x,y)))
 background=statistics.median(annulus)
 peak=max(light for _,_,light in pixels)-background
 assert peak>max(.005,background*.5),(name,'Disk not sufficiently brighter than background',peak,background)
 diskPixels=sum(light-background>peak*.2 for _,_,light in pixels)
 assert diskPixels>=7,(name,'Detected a point star rather than the celestial disk',diskPixels)
 weights=[(x,y,max(0,light-background)) for x,y,light in pixels]
 total=sum(w for _,_,w in weights);assert total>0.0001,(name,'No visible disk')
 measured=[sum(x*w for x,_,w in weights)/total,sum(y*w for _,y,w in weights)/total]
 error=math.dist(measured,fixture['pixel']);assert error<2.5,(name,measured,fixture['pixel'],error)
 results.append({**fixture,'measuredPixel':measured,'projectionErrorPixels':error,'diskPixels':diskPixels,'diskContrast':peak,'diagnostics':d})
 print(f'PASS: {name}: disk detected within {error:.3f} pixels of orbit projection; zero windows',flush=True)
pairs=[]
for body in ['sun','moon']:
 a,b=[r for r in results if r['body']==body]
 assert a['heading']==b['heading'] and a['anchorUTC']==b['anchorUTC'] and b['verifyFrame']>a['verifyFrame']
 expected=[b['pixel'][i]-a['pixel'][i] for i in range(2)]
 measured=[b['measuredPixel'][i]-a['measuredPixel'][i] for i in range(2)]
 assert math.hypot(*measured)>20 and math.dist(expected,measured)<4
 pairs.append({'body':body,'minutes':(b['utc']-a['utc'])/60,'fixedHeading':a['heading'],'expectedDisplacementPixels':expected,'measuredDisplacementPixels':measured})
report={'passed':True,'trajectory':trajectory,'renders':results,'motionPairs':pairs,'scope':'24-hour cached trajectory and actual GPU disk positions/motion. Each late capture runs from the same initial UTC as its early pair for 188 frames, so stale/frozen uniforms or sky cache cannot pass by restarting at the final date. Fixed camera, no windows/network/user-cache writes.'}
(out/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS: both celestial disks move across the rendered sky with a fixed camera.',flush=True)
