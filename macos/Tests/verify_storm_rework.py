#!/usr/bin/env python3
"""Render actual 3D rain/depth pairs and continuous cloud formation footage."""
import json,subprocess,struct,os
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw
root=Path(__file__).resolve().parents[2];out=root/'macos/build/storm-rework';out.mkdir(exist_ok=True)
app=root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
report=out/'verification.json';report.unlink(missing_ok=True)
def run(name,settings,validation=False):
 query={'fixedDt':0,'time':30,'sunElev':20,'storm':1,'dump':out/name,**settings}
 env=os.environ.copy()
 if validation:env.update(MTL_DEBUG_LAYER='1',MTL_SHADER_VALIDATION='1')
 p=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in query.items())],capture_output=True,text=True,env=env,timeout=240)
 (out/f'{name}.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stdout+p.stderr
 d=[json.loads(s.removeprefix('Ocean diagnostics: ')) for s in p.stdout.splitlines() if s.startswith('Ocean diagnostics: ')]
 assert d and all(s['offscreen'] and s['windowCount']==0 and s['activationPolicy']==2 and not s['errors'] for s in d)
 print('PASS:',name,flush=True);return d
cases={}
for name,settings in [('rain-depth',{}),('rain-none',{'rainParticles':0}),('rain-no-depth',{'rainOcclusion':0}),('drizzle',{'storm':0.08}),('night',{'dayNight':1,'latitude':40.7128,'longitude':-74.006,'timeZone':'America/New_York','utc':1793417400}),('portrait',{'renderWidth':759,'renderHeight':1349})]:
 cases[name]=run(name,settings,True)[-1]
def hdr(name):return np.fromfile(out/name,dtype='<f2').astype(np.float32).reshape(800,1280,4)[:,:,:3]
on,off,unoccluded=[hdr(n) for n in ['rain-depth','rain-none','rain-no-depth']]
particlePixels=int((np.max(np.abs(on-off),axis=2)>0.0001).sum())
occludedPixels=int((np.max(np.abs(on-unoccluded),axis=2)[350:,:]>0.0001).sum())
assert particlePixels>1000,particlePixels
assert occludedPixels>200,occludedPixels
# Full-frame native captures from ONE simulation, without crossfading images.
frames=list(range(12,373,3));formation=run('buildup',{'storm':0,'weatherFrom':0,'weatherTo':1,'weatherChangeAt':1,'utc':1793394900,'cycleRate':10,'dayNight':0,'time':0,'fixedDt':1/30,'captureFrames':','.join(map(str,frames)),'captureDisplayOnly':1,'dumpClouds':1,'renderWidth':960,'renderHeight':600})
for k in frames:assert (out/f'buildup-{k:04d}.bgra8').stat().st_size==960*600*4
motionFrames=list(range(8,69));run('rain-motion',{'fixedDt':1/30,'captureFrames':','.join(map(str,motionFrames)),'captureDisplayOnly':1,'renderWidth':960,'renderHeight':600})
def mask(k):
 data=(out/f'buildup-{k:04d}.clouds').read_bytes()[:480*300*8]
 return np.frombuffer(data,dtype='<f2').reshape(300,480,4)[:120,:,3].astype(np.float32)
initial=float((mask(frames[0])<0.35).mean());final=float((mask(frames[-1])<0.35).mean())
assert final>initial+0.15,(initial,final)
def video(prefix,ids,fps):
 destination=out/f'{prefix}.mp4'
 p=subprocess.Popen(['ffmpeg','-loglevel','error','-y','-f','rawvideo','-pixel_format','bgra','-video_size','960x600','-framerate',str(fps),'-i','-','-an','-c:v','libx264','-preset','fast','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',str(destination)],stdin=subprocess.PIPE)
 for k in ids:p.stdin.write((out/f'{prefix}-{k:04d}.bgra8').read_bytes())
 p.stdin.close();assert p.wait()==0
video('buildup',frames,10);video('rain-motion',motionFrames,30)
review=Image.new('RGB',(1440,1125))
for i,k in enumerate([12,84,120,180,252,372]):
 im=Image.frombytes('RGBA',(960,600),(out/f'buildup-{k:04d}.bgra8').read_bytes(),'raw','BGRA').convert('RGB').resize((720,450)).crop((0,0,720,375));ImageDraw.Draw(im).text((12,12),f'{max(0,(k-30)/3):.0f} simulated seconds',fill='white');review.paste(im,((i%2)*720,(i//2)*375))
review.save(out/'buildup-review.png')
report.write_text(json.dumps({'passed':True,'rainVisiblePixels':particlePixels,'rainPixelsHiddenByActualWaveDepth':occludedPixels,'upperSkyOpaqueCoverageBefore':initial,'upperSkyOpaqueCoverageAfter':final,'cases':cases,'formation':formation,'movies':{'buildup':'buildup.mp4','rainMotion':'rain-motion.mp4'},'scope':'Real native frames from persistent simulation; no image blending/interpolation. Buildup is accelerated; rain-motion is normal speed. Depth override is diagnostic only. Numeric coverage/occlusion gates supplement, not replace, visual review.'},indent=2)+'\n')
print('PASS: physical depth occlusion and continuous volumetric formation; review movies.',flush=True)
