#!/usr/bin/env python3
"""Headless visual fixtures, finite GPU output and cloud clock regression gates."""
import json
from pathlib import Path
import subprocess
import struct

root=Path(__file__).resolve().parents[2]
app=root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
out=root/'macos/build/volumetric-clouds';out.mkdir(exist_ok=True)
scenes={
    'sunset':{'time':5},
    'daylight':{'time':120,'sunElev':35,'clouds':0.5},
    'overcast':{'time':45,'clouds':1,'veil':0.8,'haze':8},
    'clear':{'time':15,'clouds':0,'veil':0},
    'clear_legacy':{'time':15,'clouds':0,'veil':0,'volumetricClouds':0},
    'high_only':{'time':30,'clouds':0,'veil':0.7},
    'low_only':{'time':30,'clouds':0.5,'veil':0},
    'night':{'time':30,'sunElev':-12,'clouds':0.6},
    'zenith':{'time':30,'sunElev':90,'clouds':0.5},
    'portrait':{'time':15,'renderWidth':759,'renderHeight':1349},
    'ultrawide':{'time':30,'renderWidth':1908,'renderHeight':537},
    'month':{'time':2592000,'skyOnly':1},
    'before_rebase':{'time':599.99,'skyOnly':1},
    'after_rebase':{'time':600.01,'skyOnly':1},
}
results=[]
for name,settings in scenes.items():
    target=out/f'{name}.rgba16f'
    q={'fixedDt':0,'dumpClouds':1,'dump':target,**settings}
    p=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in q.items())],capture_output=True,text=True,timeout=90)
    (out/f'{name}.log').write_text(p.stdout+p.stderr)
    assert p.returncode==0,p.stdout+p.stderr
    d=json.loads(next(line.removeprefix('Ocean diagnostics: ') for line in p.stdout.splitlines() if line.startswith('Ocean diagnostics: ')))
    assert d['offscreen'] and d['windowCount']==0 and d['activationPolicy']==2
    assert not d['errors'] and d['volumetricClouds']==(settings.get('volumetricClouds',1)!=0)
    # Readbacks verify cached sky, every environment face/mip and sun visibility
    # inside OceanRenderer, in addition to the full HDR/display finite checks.
    cloud_capture=Path(str(target)+'.clouds').read_bytes()
    sun_visibility=struct.unpack('<f',cloud_capture[-4:])[0]
    assert 0 <= sun_visibility <= 1,('Invalid sun transmission',sun_visibility)
    results.append({'scene':name,'settings':settings,'diagnostics':d})
    print(f'PASS: {name} ({d["width"]}x{d["height"]}), zero windows',flush=True)
assert (out/'clear.rgba16f').read_bytes()==(out/'clear_legacy.rgba16f').read_bytes(),'No-cloud HDR must match reference exactly'
assert (out/'clear.rgba16f.bgra8').read_bytes()==(out/'clear_legacy.rgba16f.bgra8').read_bytes(),'No-cloud display must match reference exactly'
# The sky-only comparison isolates procedural cloud motion at the phase rebase.
a=(out/'before_rebase.rgba16f').read_bytes();b=(out/'after_rebase.rgba16f').read_bytes()
error=0.; reference=0.; peak=0.
for (x,),(y,) in zip(struct.iter_unpack('<e',a),struct.iter_unpack('<e',b)):
    delta=abs(x-y);error+=delta*delta;reference+=x*x;peak=max(peak,delta)
relative=(error/max(reference,1e-30))**0.5
assert relative<0.005,('Cloud motion jumped at wave rebase',relative)
report={'passed':True,'cases':results,'clearLegacyHDRAndDisplayExact':True,'rebaseRelativeL2':relative,'rebaseMaxAbsoluteHDRDelta':peak,'scope':'Finite output, headless lifecycle, clear bypass and clock continuity. Images require visual review; not proof of physical accuracy or energy savings.'}
(out/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(f'PASS: exact clear-sky bypass; 600 s sky continuity relative L2={relative:.6g}',flush=True)
