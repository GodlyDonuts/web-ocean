#!/usr/bin/env python3
"""Compare GPU sky output across the old wrap and at a month of uptime."""
import json
import math
from pathlib import Path
import subprocess

root=Path(__file__).resolve().parents[2]
output=root/'macos/build/time-quality'
output.mkdir(exist_ok=True)
app=root/'macos/build/Ocean.app/Contents/MacOS/Ocean'

def capture(name,time,mode='continuous',step=0,sky_only=True):
    path=output/f'{name}.rgba16f'
    query={'time':time,'clock':mode,'fixedDt':step,'skyOnly':int(sky_only),'fullSky':1,'dump':path}
    process=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in query.items())],capture_output=True,text=True,timeout=90)
    if process.returncode: raise RuntimeError(process.stdout+'\n'+process.stderr)
    diagnostic=json.loads(next(line.removeprefix('Ocean diagnostics: ') for line in process.stdout.splitlines() if line.startswith('Ocean diagnostics: ')))
    assert diagnostic['offscreen'] and diagnostic['windowCount']==0 and diagnostic['activationPolicy']==2, 'Automated render must not create or activate windows'
    assert not diagnostic['errors']
    assert diagnostic['stableDetails']==(mode=='continuous' and diagnostic['elapsed']>=600)
    return Path(str(path)+'.bgra8').read_bytes(),diagnostic

def difference(a,b):
    assert len(a)==len(b)
    squares=0;maximum=0;changed=0
    for x,y in zip(a,b):
        delta=abs(x-y);squares+=delta*delta;maximum=max(maximum,delta);changed+=delta!=0
    return {'rmsByteError':math.sqrt(squares/len(a)),'maximumByteError':maximum,'changedBytes':changed}

before,_=capture('before-wrap',599.95)
after,diagnostic=capture('after-wrap',600.05)
old_before,_=capture('legacy-before-wrap',599.95,'legacy')
old_after,_=capture('legacy-after-wrap',600.05,'legacy')
reference,_=capture('unwrapped-after',600.05,'unwrapped')
new_delta=difference(before,after)
old_delta=difference(old_before,old_after)
reference_error=difference(after,reference)
print(json.dumps({'newTransition':new_delta,'legacyTransition':old_delta,'unwrappedReferenceError':reference_error}),flush=True)
assert new_delta['rmsByteError']<old_delta['rmsByteError']*0.1, 'The ten-minute visual jump remains'
assert reference_error['rmsByteError']<1 and reference_error['maximumByteError']<16, 'Rebased clouds disagree with the unwrapped reference'

handover,handover_diagnostic=capture('handover',599.9,step=0.0333333333)
handover_reference,_=capture('handover-reference',handover_diagnostic['cachedSkyElapsed'])
handover_error=difference(handover,handover_reference)
print(json.dumps({'pipelineHandoverError':handover_error}),flush=True)
assert handover_error['changedBytes']==0, 'The first clock handover used incorrect or uninitialized cloud data'

ocean,_=capture('ocean-after-wrap',600.05,sky_only=False)
ocean_reference,_=capture('ocean-unwrapped-reference',600.05,'unwrapped',sky_only=False)
ocean_error=difference(ocean,ocean_reference)
print(json.dumps({'oceanReferenceError':ocean_error}),flush=True)
assert ocean_error['rmsByteError']<1 and ocean_error['maximumByteError']<16, 'Bounded gust/foam phases disagree with the unwrapped reference'

uptime=30*86400
month_a,_=capture('month-a',uptime)
month_b,_=capture('month-b',uptime+0.125)
float_a,_=capture('float-month-a',uptime,'unwrapped')
float_b,_=capture('float-month-b',uptime+0.125,'unwrapped')
month_motion=difference(month_a,month_b)
float_motion=difference(float_a,float_b)
print(json.dumps({'monthMotion':month_motion,'naiveFloatMotion':float_motion}),flush=True)
assert month_motion['changedBytes']>0, 'Cloud advection has lost subsecond motion'
assert float_motion['changedBytes']==0, 'The test must reproduce the naive float-clock freeze'
report={'passed':True,'beforeTime':599.95,'afterTime':600.05,'newTransition':new_delta,'legacyTransition':old_delta,'unwrappedReferenceError':reference_error,'monthUptimeSeconds':uptime,'monthMotion':month_motion,'naiveFloatMotion':float_motion,'pipelineHandoverError':handover_error,'oceanReferenceError':ocean_error,'handoverDiagnostics':handover_diagnostic,'diagnostics':diagnostic}
(output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS: no ten-minute cloud reset; rebased cloud motion remains responsive after a month.',flush=True)
