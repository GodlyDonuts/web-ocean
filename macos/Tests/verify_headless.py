#!/usr/bin/env python3
"""Exercise GPU verification, benchmark and failure paths without creating windows.

Optional saved fixtures prove parity with earlier windowed captures without
launching a windowed process. The default gate needs no saved fixtures.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import uuid

parser=argparse.ArgumentParser()
parser.add_argument('--windowed-fixtures',type=Path)
args=parser.parse_args()
root=Path(__file__).resolve().parents[2]
app=root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
output=root/'macos/build/headless'
output.mkdir(exist_ok=True)
report_path=output/'report.json'
report_path.unlink(missing_ok=True)
cases={
    'sunset':{}, 'swell_phase_45':{'time':45}, 'swell_phase_120':{'time':120},
    'daylight':{'time':60,'sunElev':35,'clouds':0.1},
    'rough_cloudy':{'time':90,'sunElev':8,'windSpeed':12,'swellHs':2.5,'clouds':0.8,'haze':8},
    'ultrawide':{'renderWidth':1908,'renderHeight':537,'time':30},
    'portrait':{'renderWidth':759,'renderHeight':1349,'time':15},
    'wide_16_9':{'renderWidth':1349,'renderHeight':759,'time':20},
    'index_fallback':{'renderWidth':62,'renderHeight':16384,'time':5},
    'stable_time':{'time':600.05},'month_uptime':{'time':2592000},
    'narrow_stable':{'renderWidth':253,'renderHeight':4048,'time':600.05},
}
if args.windowed_fixtures is None:
    cases={name:cases[name] for name in ['sunset','portrait','narrow_stable']}
else:
    args.windowed_fixtures=args.windowed_fixtures.resolve()
    for name in cases:
        for suffix in ['', '.bgra8','.mips']:
            assert (args.windowed_fixtures/f'{name}-optimized.rgba16f{suffix}').is_file(), (name,suffix)

def check_background(data):
    assert data['offscreen'] and data['windowCount']==0 and data['activationPolicy']==2, data
    assert not data['errors'], data['errors']

results=[]
for name,settings in cases.items():
    capture=output/f'{name}.rgba16f'
    query={'fixedDt':'0.0333333333',**settings}
    if args.windowed_fixtures is not None:
        query.update(dump=str(capture),dumpMips=1)
        for suffix in ['', '.bgra8','.mips']: Path(str(capture)+suffix).unlink(missing_ok=True)
    process=subprocess.run([str(app),'--verify','--query='+'&'.join(f'{k}={v}' for k,v in query.items())],capture_output=True,text=True,check=True,timeout=90)
    diagnostic=json.loads(next(line.removeprefix('Ocean diagnostics: ') for line in process.stdout.splitlines() if line.startswith('Ocean diagnostics: ')))
    check_background(diagnostic)
    compared={}
    if args.windowed_fixtures is not None:
        for suffix in ['', '.bgra8','.mips']:
            old=args.windowed_fixtures/f'{name}-optimized.rgba16f{suffix}'
            new=Path(str(capture)+suffix)
            a,b=old.read_bytes(),new.read_bytes()
            assert a and len(a)==len(b) and a==b, (name,suffix,len(a),len(b))
            compared[suffix or 'HDR']={'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest(),'fixture':str(old)}
        for suffix in ['', '.bgra8','.mips']: Path(str(capture)+suffix).unlink()
    result={'case':name,'diagnostics':diagnostic,'windowedParity':compared}
    results.append(result)
    print(json.dumps({'case':name,'windows':diagnostic['windowCount'],'matchedCaptures':len(compared)}),flush=True)

benchmark_path=output/'benchmark.json'
benchmark_path.unlink(missing_ok=True)
subprocess.run([str(app),'--benchmark',f'--query=fixedDt=0.0333333333&frames=72&report={benchmark_path}'],capture_output=True,text=True,check=True,timeout=90)
benchmark=json.loads(benchmark_path.read_text());check_background(benchmark)
assert benchmark['samples']==12 and not benchmark['profiled'] and benchmark['gpuMedianMs']>0
failures=[]
missing=output/f'missing-{uuid.uuid4()}.metal'
for mode in ['--verify','--benchmark']:
    process=subprocess.run([str(app),mode,f'--query=referenceOcean={missing}'],capture_output=True,text=True,timeout=90)
    assert process.returncode!=0 and 'Ocean failed:' in process.stderr,(mode,process.returncode,process.stderr)
    failures.append({'mode':mode,'exitCode':process.returncode,'message':process.stderr.strip()})
report={'passed':True,'cases':results,'benchmarkSmoke':benchmark,'startupFailures':failures,
        'scope':'No NSWindow or drawable acquisition, application activation policy prohibited; original windowed captures used only as saved fixtures. The 12-sample benchmark is a lifecycle smoke test, not a performance comparison.'}
report_path.write_text(json.dumps(report,indent=2)+'\n')
print('PASS: windowless verification, benchmark and startup-failure paths.',flush=True)
