#!/usr/bin/env python3
"""Interleaved ABBA comparison of ordinary frame command-buffer GPU times."""
import argparse
import json
import math
from pathlib import Path
import statistics
import struct
import subprocess
root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--reference-app',type=Path,help='Compare batch bindings against a separately built accepted reference executable')
parser.add_argument('--clouds',type=float)
parser.add_argument('--veil',type=float)
parser.add_argument('--time',type=float,default=0)
parser.add_argument('--render-width',type=int)
parser.add_argument('--render-height',type=int)
parser.add_argument('--mip-mode',type=int,default=2,choices=[2])
parser.add_argument('--rounds',type=int,default=1,help='ABBA rounds; alternate round order to counter drift')
parser.add_argument('--shared-lighting',action='store_true',help='Enable the experimental shared lighting cache in optimized runs')
parser.add_argument('--baseline',choices=['original','previous','bindings','mips','guard','packed','clock','clouds','cubic','evolution','inactiveaa','textureusage','batchbindings'],default='original')
args = parser.parse_args()
if args.reference_app is not None and (args.baseline != 'batchbindings' or not args.reference_app.is_file()): parser.error('--reference-app requires --baseline batchbindings and an existing executable')
if args.rounds < 1: parser.error('--rounds must be positive')
for name in ['clouds','veil']:
    value = getattr(args,name)
    if value is not None and (not math.isfinite(value) or abs(value)>3.4e38): parser.error(f'--{name} must be finite and representable as float32')
def cloud_enabled(value):
    return struct.unpack('<f',struct.pack('<f',value))[0] > struct.unpack('<f',struct.pack('<f',0.001))[0]
output = root / 'macos/build/benchmarks' / (args.baseline if args.rounds == 1 else f'{args.baseline}-{args.rounds}-rounds')
if args.render_width is not None:
    output = output.with_name(output.name+f'-{args.render_width}x{args.render_height}')
if args.time: output = output.with_name(output.name+f'-t{args.time:g}')
if args.clouds is not None: output = output.with_name(output.name+f'-c{args.clouds:g}')
if args.veil is not None: output = output.with_name(output.name+f'-v{args.veil:g}')
if args.reference_app is not None: output = output.with_name(output.name+'-external')
output.mkdir(exist_ok=True,parents=True)
(output/'report.json').unlink(missing_ok=True)
runs = []
order = tuple(value for round_index in range(args.rounds) for value in ((True,False,False,True) if round_index%2 == 0 else (False,True,True,False)))
for i, baseline in enumerate(order):
    path = output / f'run-{i}.json'
    path.unlink(missing_ok=True)  # A failed run must never reuse an earlier result.
    query = {'fixedDt': '0.0333333333', 'frames': 180, 'report': path}
    if args.render_width is not None or args.render_height is not None:
        if any(value is None or value < 1 for value in [args.render_width,args.render_height]): parser.error('Supply both positive --render-width and --render-height')
        query.update(renderWidth=args.render_width,renderHeight=args.render_height)
    if args.time: query['time'] = args.time
    if args.clouds is not None: query['clouds'] = args.clouds
    if args.veil is not None: query['veil'] = args.veil
    if args.baseline == 'batchbindings': query['batchBindings'] = 0 if baseline else 1
    if args.baseline == 'textureusage': query['narrowTextureUsage'] = 0 if baseline else 1
    if args.baseline == 'inactiveaa': query['pruneCloudAA'] = 0 if baseline else 1
    if args.baseline == 'evolution':
        query['fusedEvolution'] = 0 if baseline else 1
    if args.baseline == 'cubic':
        query['sharedCubic'] = 0 if baseline else 1
    if args.baseline == 'clouds':
        query['skipCloudOctaves'] = 0 if baseline else 1
    if args.baseline == 'clock':
        query['clock'] = 'unwrapped' if baseline else 'continuous'
    if baseline and args.baseline in ['original','previous']:
        query['fusedEvolution'] = 0
        query['skipCloudOctaves'] = 0
        query['packedJacobian'] = 0
    if args.baseline == 'packed':
        query['packedJacobian'] = 0 if baseline else 1
    if args.baseline == 'guard':
        query['legacyGuard'] = 1 if baseline else 0
    if not baseline and args.shared_lighting:
        query['sharedLighting'] = 1
    if args.baseline == 'bindings':
        query['fusedMips'] = 0
    if args.baseline == 'mips':
        query['fusedMips'] = 0 if baseline else args.mip_mode
    if baseline and args.baseline not in ['mips','guard','packed','clock','clouds','cubic','evolution','inactiveaa','textureusage','batchbindings']:
        query['verboseBindings'] = 1
        query['fusedMips'] = 0
        if args.baseline != 'bindings':
            query.update(perPixelLighting=1,wideIndices=1)
        if args.baseline == 'original':
            query.update(fullSky=1,dynamicUniforms=1,referenceOcean=root / 'macos/Tests/OCEAN_REFERENCE.metal')
    query_string = '&'.join(f'{k}={v}' for k,v in query.items())
    executable = args.reference_app.resolve() if baseline and args.reference_app is not None else root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
    subprocess.run([str(executable), '--benchmark', f'--query={query_string}'], cwd=root, check=True, capture_output=True, timeout=90)
    report = json.loads(path.read_text())
    report['reference'] = baseline
    report['query'] = {k:str(v) for k,v in query.items()}
    assert not report['errors'] and not report['profiled']
    assert all(math.isfinite(report[key]) and report[key] > 0 for key in ['cpuThreadEncodeMeanMs','cpuThreadEncodeMedianMs'])
    if args.baseline == 'inactiveaa':
        mask = (1 if cloud_enabled(0.4 if args.clouds is None else args.clouds) else 0) | (2 if cloud_enabled(0.36 if args.veil is None else args.veil) else 0)
        assert report['skyAAMask'] == (3 if baseline else mask)
    if args.baseline == 'batchbindings': assert report.get('batchedBindings',False) == (not baseline)
    if args.baseline == 'textureusage': assert report['narrowTextureUsage'] == (not baseline)
    if args.baseline == 'evolution':
        assert report['fusedEvolution'] == (not baseline)
        assert report['spectrumBufferBytes'] == (12*1024*1024 if baseline else 0)
    if args.baseline == 'cubic': assert report['sharedCubic'] == (not baseline)
    runs.append(report)
    print(json.dumps({'run':i,'reference':baseline,'medianMs':report['gpuMedianMs'],'p95Ms':report['gpuP95Ms']}),flush=True)
reference = statistics.mean(r['gpuMedianMs'] for r in runs if r['reference'])
optimized = statistics.mean(r['gpuMedianMs'] for r in runs if not r['reference'])
timings = {}
for metric in ['gpuMeanMs','gpuMedianMs','gpuP95Ms','cpuEncodeMeanMs','cpuEncodeMedianMs','cpuThreadEncodeMeanMs','cpuThreadEncodeMedianMs']:
    before = statistics.mean(r[metric] for r in runs if r['reference'])
    after = statistics.mean(r[metric] for r in runs if not r['reference'])
    timings[metric] = {'referenceAverageMs':before,'optimizedAverageMs':after,'reductionPercent':100*(1-after/before)}
report = {'referenceApp':str(args.reference_app.resolve()) if args.reference_app else None,'baseline':args.baseline,'rounds':args.rounds,'mipMode':args.mip_mode,'sharedLighting':args.shared_lighting,'timings':timings,'referenceMedianAverageMs':reference,'optimizedMedianAverageMs':optimized,'reductionPercent':100*(1-optimized/reference),'runs':runs}
(output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k != 'runs'}),flush=True)
