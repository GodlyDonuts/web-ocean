#!/usr/bin/env python3
"""macOS process CPU/physical footprint plus renderer GPU timing, without root.

CPU 100% means one CPU core. GPU time is command-buffer work, not whole-device
utilization/power. Unified-memory footprint and Metal allocation overlap: do not add.
"""
import argparse,ctypes,json,statistics,subprocess,time
from pathlib import Path

class Usage(ctypes.Structure):
    _fields_=[('uuid',ctypes.c_uint8*16)]+[(name,ctypes.c_uint64) for name in
      ['user','system','pkgWakeups','interruptWakeups','pageins','wired','resident','footprint',
       'start','exit','childUser','childSystem','childPkgWakeups','childInterruptWakeups',
       'childPageins','childElapsed','diskRead','diskWrite']]
class Timebase(ctypes.Structure):
    _fields_=[('numer',ctypes.c_uint32),('denom',ctypes.c_uint32)]
timebase=Timebase()
ctypes.CDLL('/usr/lib/libSystem.B.dylib').mach_timebase_info(ctypes.byref(timebase))
# rusage_info CPU times use Mach absolute ticks on macOS, not nanoseconds.
# Calibrated against a child process's process_time CPU clock.
cpu_ns_per_tick=timebase.numer/timebase.denom
lib=ctypes.CDLL('/usr/lib/libproc.dylib',use_errno=True)
lib.proc_pid_rusage.argtypes=[ctypes.c_int,ctypes.c_int,ctypes.c_void_p];lib.proc_pid_rusage.restype=ctypes.c_int

def usage(pid):
    u=Usage()
    if lib.proc_pid_rusage(pid,2,ctypes.byref(u)):raise OSError(ctypes.get_errno(),'proc_pid_rusage')
    return {'cpuNs':round((u.user+u.system)*cpu_ns_per_tick),'physicalBytes':u.footprint,'residentBytes':u.resident,'wakeups':u.pkgWakeups+u.interruptWakeups}
root=Path(__file__).resolve().parents[2]
ny={'dayNight':1,'latitude':40.7128,'longitude':-74.006,'timeZone':'America/New_York'}
scenes={'noon':{**ny,'utc':1793378400,'heading':180},
 'moonless':{**ny,'utc':1794283200,'heading':270,'clouds':.12,'veil':.05},
 'moonlit':{**ny,'utc':1793412600,'heading':60,'clouds':.15,'veil':.1},
 'storm':{**ny,'utc':1794283200,'heading':270,'storm':1}}

def run(app,out,name,settings,frames=360,profile=False,extra=None):
    out.mkdir(exist_ok=True,parents=True);report=out/f'{name}.json';report.unlink(missing_ok=True)
    q={'frames':frames,'fixedDt':1/30,'report':str(report),**settings,**(extra or {})}
    cmd=[str(app/'Contents/MacOS/Ocean'),'--benchmark']+(['--profile'] if profile else [])+['--query='+'&'.join(f'{k}={v}' for k,v in q.items())]
    samples=[];start=time.monotonic()
    with (out/f'{name}.log').open('w') as log:
        p=subprocess.Popen(cmd,stdout=log,stderr=log)
        try:
            while p.poll() is None:
                now=time.monotonic()
                try:samples.append({'t':now-start,**usage(p.pid)})
                except OSError:pass
                if now-start>180:raise TimeoutError('Resource benchmark timed out')
                time.sleep(.25)
            if p.returncode:raise RuntimeError(f'Benchmark failed: {out/name}.log')
        finally:
            if p.poll() is None:p.kill();p.wait()
    d=json.loads(report.read_text());assert d['offscreen'] and d['windowCount']==0 and not d['errors'] and d['solarCacheWrites']==0
    measured=[s for s in samples if s['t']>=3]
    assert len(measured)>=4,'Insufficient steady-state process samples'
    a,b=measured[0],measured[-1];duration=b['t']-a['t']
    cpu=(b['cpuNs']-a['cpuNs'])/1e9/duration*100
    summary={'steadyCPUPercentOneCore':cpu,'physicalFootprintMedianMiB':statistics.median(s['physicalBytes'] for s in measured)/2**20,
      'physicalFootprintPeakMiB':max(s['physicalBytes'] for s in samples)/2**20,
      'residentMedianMiB':statistics.median(s['residentBytes'] for s in measured)/2**20,
      'processWakeupsPerSecond':(b['wakeups']-a['wakeups'])/duration,'sampleSeconds':duration}
    result={'settings':q,'process':summary,'renderer':d,'samples':measured,'profiled':profile,'cpuMachTimebase':{'numer':timebase.numer,'denom':timebase.denom}}
    (out/f'{name}-resources.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'case':name,**summary,'gpuMeanMs':d['gpuMeanMs'],'gpuP95Ms':d['gpuP95Ms'],'gpuStagesMs':d['gpuStagesMs']}),flush=True)
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--app',type=Path,default=root/'macos/build/Ocean.app')
    p.add_argument('--out',type=Path,default=root/'macos/build/resource-benchmark');p.add_argument('--scenes',default='noon,moonless,storm')
    p.add_argument('--frames',type=int,default=360);p.add_argument('--profile',action='store_true');p.add_argument('--extra',default='')
    args=p.parse_args();extra=dict(item.split('=',1) for item in args.extra.split('&') if item)
    results={name:run(args.app.resolve(),args.out,name,scenes[name],args.frames,args.profile,extra) for name in args.scenes.split(',')}
    (args.out/'summary.json').write_text(json.dumps({'cases':results,'scope':__doc__,'powerCounters':'Unavailable without superuser access; no power/battery claim.','captureMode':'Offscreen, 1280x800 default, 30 FPS cap; excludes WindowServer/display presentation. Process samples exclude the first 3 seconds; GPU samples exclude 60 warmup frames.'},indent=2)+'\n')
