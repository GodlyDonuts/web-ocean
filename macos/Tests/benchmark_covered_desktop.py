#!/usr/bin/env python3
"""Measure one actual fully covered desktop startup; does not change settings.

Opens a temporary wallpaper process once, samples it, then terminates that PID.
Requires the desktop to remain covered. Uses a fixed reference sky, no providers.
"""
import argparse,importlib.util,json,os,statistics,subprocess,time
from pathlib import Path
spec=importlib.util.spec_from_file_location('resources',Path(__file__).with_name('benchmark_resources.py'))
resources=importlib.util.module_from_spec(spec);spec.loader.exec_module(resources)
root=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--app',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--seconds',type=float,default=24)
a=p.parse_args();app=a.app.resolve();binary=str(app/'Contents/MacOS/Ocean');out=a.out;out.mkdir(exist_ok=True,parents=True)
log=out/'desktop.log';err=out/'desktop.err';log.unlink(missing_ok=True);err.unlink(missing_ok=True)
def matching_pids():
 rows=subprocess.check_output(['ps','-axo','pid=,args='],text=True).splitlines()
 return {int(r.strip().split(None,1)[0]) for r in rows if r.strip().split(None,1)[-1].startswith(binary+' --diagnostics')}
existing=matching_pids()
subprocess.run(['open','-n','-g','-a',str(app),'--stdout',str(log.resolve()),'--stderr',str(err.resolve()),'--args','--diagnostics','--query=dayNight=0&weather=0'],check=True)
pid=None;samples=[];start=time.monotonic()
try:
 while time.monotonic()-start<a.seconds:
  if pid is None:
   matches=matching_pids()-existing
   assert len(matches)<=1,'Cannot uniquely identify temporary wallpaper process'
   if matches:pid=matches.pop()
  if pid is not None:
   try:samples.append({'t':time.monotonic()-start,**resources.usage(pid)})
   except OSError:raise RuntimeError('Wallpaper process exited while sampling')
  time.sleep(.5)
 lines=log.read_text().splitlines() if log.exists() else []
 diagnostics=[json.loads(s.removeprefix('Ocean diagnostics: ')) for s in lines if s.startswith('Ocean diagnostics: ')]
 assert len(diagnostics)>=2 and all(not d['errors'] and d['frames']==0 and d['paused'] for d in diagnostics),'Desktop was not fully covered/idle; no idle measurement claimed'
 steady=[s for s in samples if s['t']>=8];assert len(steady)>=8
 first,last=steady[0],steady[-1];dt=last['t']-first['t']
 result={'passed':True,'CPUPercentOneCore':(last['cpuNs']-first['cpuNs'])/1e9/dt*100,
  'physicalFootprintMedianMiB':statistics.median(s['physicalBytes'] for s in steady)/2**20,
  'wakeupsCounterPerSecond':(last['wakeups']-first['wakeups'])/dt,'sampleSeconds':dt,
  'gpuFrames':0,'gpuMs':0,'diagnostics':diagnostics,'scope':'Actual covered-desktop startup with fixed reference sky/providers off; scene targets not allocated yet. Retained memory after a previously visible session is not measured here.'}
 (out/'summary.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:v for k,v in result.items() if k!='diagnostics'}))
finally:
 if pid is not None:
  try:os.kill(pid,15)
  except ProcessLookupError:pass
