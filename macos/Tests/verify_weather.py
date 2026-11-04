#!/usr/bin/env python3
"""Native GPU storm range, wave growth, continuous transition and lifecycle."""
import json,math,struct,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[2];out=root/'macos/build/weather';out.mkdir(exist_ok=True)
app=root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
(out/'verification.json').unlink(missing_ok=True)
scenes={
 'fair':{'storm':0},'drizzle':{'storm':0.08},'rain':{'storm':0.4},'thunderstorm':{'storm':0.75},'hurricane':{'storm':1},
 'hurricane_night':{'storm':1,'dayNight':1,'latitude':40.7128,'longitude':-74.006,'utc':1793417400,'timeZone':'America/New_York'},
 'lightning':{'storm':1,'time':5.715996918678284},
 'portrait':{'storm':1,'renderWidth':759,'renderHeight':1349},
 'transition_before':{'weatherFrom':0,'weatherTo':1,'weatherChangeAt':1,'time':0,'fixedDt':1/30,'verifyFrame':29},
 'transition_start':{'weatherFrom':0,'weatherTo':1,'weatherChangeAt':1,'time':0,'fixedDt':1/30,'verifyFrame':30},
 'transition_middle':{'weatherFrom':0,'weatherTo':1,'weatherChangeAt':1,'time':0,'fixedDt':1,'verifyFrame':60},
 'transition_late':{'weatherFrom':0,'weatherTo':1,'weatherChangeAt':1,'time':0,'fixedDt':1,'verifyFrame':188},
 'settling':{'weatherFrom':1,'weatherTo':0.08,'weatherChangeAt':1,'time':0,'fixedDt':1,'verifyFrame':188},
 'month_turn_before':{'weatherFrom':0,'weatherTo':1,'weatherHeadingTo':250,'weatherChangeAt':1,'time':2592000,'fixedDt':1/30,'verifyFrame':29},
 'month_turn_after':{'weatherFrom':0,'weatherTo':1,'weatherHeadingTo':250,'weatherChangeAt':1,'time':2592000,'fixedDt':1/30,'verifyFrame':30},
 'rain_wrap_before':{'storm':1,'time':53247.99},'rain_wrap_after':{'storm':1,'time':53248.01},'rain_wrap_control':{'storm':1,'time':53248.03},
}
results={};heights={};displacements={}
for name,settings in scenes.items():
 path=out/f'{name}.rgba16f'
 q={'fixedDt':0,'sunElev':20,'time':30,'dumpMips':1,'dumpClouds':1,'dump':path,**settings}
 p=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in q.items())],capture_output=True,text=True,timeout=180)
 (out/f'{name}.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stdout+p.stderr
 d=json.loads([s.removeprefix('Ocean diagnostics: ') for s in p.stdout.splitlines() if s.startswith('Ocean diagnostics: ')][-1])
 assert d['offscreen'] and d['windowCount']==0 and d['activationPolicy']==2 and not d['errors'] and d['weatherActive']
 assert 0<=d['rain']<=1 and 0<=d['weatherSeverity']<=1 and d['weatherWind']<=45.001
 assert d['solarCacheWrites']==0
 raw=Path(str(path)+'.mips').read_bytes()[:6*256*256*8]
 variance=0
 for c in range(6):
  total=squares=0.0
  for v in struct.iter_unpack('<eeee',raw[c*65536*8:(c+1)*65536*8]):
   total+=v[1];squares+=v[1]*v[1]
  variance+=max(0,squares/65536-(total/65536)**2)
 hs=4*math.sqrt(variance);heights[name]=hs
 if name in ['transition_before','transition_start']:displacements[name]=raw
 results[name]={'diagnostics':d,'spectralHeightProxyMeters':hs}
 print(f'PASS: {name}, wind {d["weatherWind"]:.2f} m/s, rain {d["rain"]:.3f}, wave-height proxy {hs:.2f} m, zero windows',flush=True)
levels=['fair','drizzle','rain','thunderstorm','hurricane']
assert all(results[b]['diagnostics']['rain']>results[a]['diagnostics']['rain'] for a,b in zip(levels,levels[1:]))
assert heights['hurricane']>heights['fair']*3 and heights['hurricane']>8,heights
assert heights['transition_before']<heights['transition_middle']<heights['transition_late'],heights
assert heights['settling']<heights['hurricane']*.6,heights
assert results['transition_start']['diagnostics']['rain']<.001
phases=[results[n]['diagnostics']['weatherDetailPhase'] for n in ['month_turn_before','month_turn_after']]
def phaseDelta(x,y):return (x-y+0.5)%1-0.5
assert all(abs(phaseDelta(x,y))<0.0005 for x,y in zip(*phases)),phases
# Directional drift has a tighter bound than the independent foam-pattern time.
assert all(abs(phaseDelta(x,y))<0.00005 for x,y in zip(phases[0][:2],phases[1][:2])),phases
# The only difference near onset should be ordinary wave motion plus a small
# amplitude relaxation. Whole-field RMS bounds reject random reseeding/reset.
a,b=displacements['transition_before'],displacements['transition_start']
error=reference=0.0
for x,y in zip(struct.iter_unpack('<eeee',a),struct.iter_unpack('<eeee',b)):
 for i in range(3):error+=(x[i]-y[i])**2;reference+=x[i]**2
relative=math.sqrt(error/reference)
assert relative<0.08,relative
assert results['transition_late']['diagnostics']['rain']>.99
# Scheduled lightning is a visible render event, not just a CPU timer.
flash=Path(str(out/'lightning.rgba16f')+'.bgra8').read_bytes()
normal=Path(str(out/'hurricane.rgba16f')+'.bgra8').read_bytes()
flashLuma=sum(flash[0::4])+sum(flash[1::4])+sum(flash[2::4])
normalLuma=sum(normal[0::4])+sum(normal[1::4])+sum(normal[2::4])
assert flashLuma>normalLuma*1.08,(flashLuma,normalLuma)
def displayDelta(a,b):
 x=Path(str(out/f'{a}.rgba16f')+'.bgra8').read_bytes();y=Path(str(out/f'{b}.rgba16f')+'.bgra8').read_bytes()
 return sum(abs(a-b) for i,(a,b) in enumerate(zip(x,y)) if i%4!=3)/(1280*800*3)
wrapDelta=displayDelta('rain_wrap_before','rain_wrap_after')
controlDelta=displayDelta('rain_wrap_after','rain_wrap_control')
assert wrapDelta<controlDelta*2.5+0.5,(wrapDelta,controlDelta)
report={'passed':True,'rainClockWrapMeanDisplayDelta':wrapDelta,'rainClockControlMeanDisplayDelta':controlDelta,'scenes':results,'onsetDisplacementRelativeL2':relative,'scope':'Real GPU readback: finite waves, sky, reflections and display; storm/drizzle range and sea buildup/settling. Height proxy is 4*sqrt(sum cascade height variances), not a measured local sea-state forecast. Fixed camera, no windows/network/user-cache writes. Images require visual review.'}
(out/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS: continuous onset, hurricane sea growth and settling, dynamic intensity range.',flush=True)
