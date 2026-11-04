#!/usr/bin/env python3
"""Compare deterministic native HDR and final display captures against the pre-optimization shader.

The comparison includes sky-work rejection. It rejects any changed half-float
channel and final display byte rather than using a perceptual threshold or resized screenshots.
"""
import argparse
import json
from pathlib import Path
import struct
import subprocess

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
mode = parser.add_mutually_exclusive_group()
mode.add_argument('--empty-foam-lighting',action='store_true',help='Isolate zero-mask foam lighting rejection')
mode.add_argument('--fused-evolution',action='store_true',help='Isolate evolution and row FFT fusion')
mode.add_argument('--shared-cubic',action='store_true',help='Isolate shared cubic reconstruction against identical native shader settings')
parser.add_argument('--skip-cloud-octaves',action='store_true')
parser.add_argument('--packed-jacobian',action='store_true')
mode.add_argument('--historical-geometry',action='store_true',help='Verify the eight unchanged layouts against the archived vertex shader')
parser.add_argument('--fused-mips',type=int,default=0,choices=[0,2])
args = parser.parse_args()
app = root / 'macos/build/Ocean.app/Contents/MacOS/Ocean'
reference = root / ('macos/Tests/Experiments/OCEAN_PRE_GUARD.metal' if args.historical_geometry else 'macos/Tests/OCEAN_REFERENCE.metal')
output = root / ('macos/build/quality-historical' if args.historical_geometry else 'macos/build/quality-foamlighting' if args.empty_foam_lighting else 'macos/build/quality-evolution' if args.fused_evolution else 'macos/build/quality-cubic' if args.shared_cubic else 'macos/build/quality')
output.mkdir(exist_ok=True)
cases = {
    'sunset': {},
    'swell_phase_45': {'time': 45},
    'swell_phase_120': {'time': 120},
    'daylight': {'time': 60, 'sunElev': 35, 'clouds': 0.1},
    'rough_cloudy': {'time': 90, 'sunElev': 8, 'windSpeed': 12, 'swellHs': 2.5, 'clouds': 0.8, 'haze': 8},
    'ultrawide': {'renderWidth': 1908, 'renderHeight': 537, 'time': 30},
    'portrait': {'renderWidth': 759, 'renderHeight': 1349, 'time': 15},
    'wide_16_9': {'renderWidth': 1349, 'renderHeight': 759, 'time': 20},
    'index_fallback': {'renderWidth': 62, 'renderHeight': 16384, 'time': 5},
}
if args.shared_cubic or args.fused_evolution or args.empty_foam_lighting:
    cases.update(stable_time={'time':600.05},month_uptime={'time':2592000},narrow_stable={'renderWidth':253,'renderHeight':4048,'time':600.05})
if args.empty_foam_lighting:
    cases.update(calm={'time':45,'windSpeed':1,'swellHs':0.1,'choppy':0.1},foam_debug={'time':15,'dbg':6})
if args.historical_geometry:
    # This layout intentionally changes geometry; its correction is checked
    # against an occupancy oracle in verify_coverage.py, not the old holes.
    cases.pop('index_fallback')
def canonical_mips(raw, packed):
    """Check the new channel against displacement.w before restoring padding.

    No existing data is masked: baseline padding must be zero and every packed
    half float must exactly duplicate the original displacement channel.
    """
    blocks = [(name,0,256,6) for name in ['displacement','slopes','moments']]
    blocks += [(name,level,256>>level,6) for name in ['displacement','slopes','moments'] for level in range(1,9)]
    blocks += [('foam',level,512>>level,2) for level in range(10)]
    result = bytearray(raw); displacement = {}; offset = 0; verified = 0
    for name,level,size,layers in blocks:
        length = size*size*layers*8
        block = raw[offset:offset+length]
        assert len(block)==length
        if name=='displacement': displacement[level] = block
        if name=='moments':
            if packed:
                assert block[6::8]==displacement[level][6::8] and block[7::8]==displacement[level][7::8], 'Packed Jacobian differs from displacement.w'
                verified += size*size*layers
            else:
                assert not any(block[6::8]) and not any(block[7::8]), 'Legacy moment padding must remain zero'
            result[offset+6:offset+length:8] = bytes(size*size*layers)
            result[offset+7:offset+length:8] = bytes(size*size*layers)
        offset += length
    assert offset==len(raw)
    return bytes(result),verified

results = []
for name, settings in cases.items():
    common = {'dumpMips':1, 'fixedDt': '0.0333333333', **settings}
    captures = []
    displays = []
    mips = []
    diagnostics = None
    for baseline in (True, False):
        path = output / f'{name}-{"reference" if baseline else "optimized"}.rgba16f'
        arguments = {**common, 'dump': str(path)}
        if not baseline and args.skip_cloud_octaves: arguments['skipCloudOctaves'] = 1
        if not baseline and args.packed_jacobian: arguments['packedJacobian'] = 1
        if not baseline and args.fused_mips: arguments['fusedMips'] = args.fused_mips
        legacy = baseline and not (args.shared_cubic or args.fused_evolution or args.empty_foam_lighting)
        if args.empty_foam_lighting: arguments['skipEmptyFoamLighting'] = 0 if baseline else 1
        elif args.fused_evolution: arguments['fusedEvolution'] = 0 if baseline else 1
        elif baseline: arguments['sharedCubic'] = 0
        if legacy:
            arguments.update(skipEmptyFoamLighting=0,fusedEvolution=0,sharedCubic=0,skipCloudOctaves=0,packedJacobian=0,fusedMips=0,verboseBindings=1,referenceOcean=str(reference), fullSky=1, dynamicUniforms=1, perPixelLighting=1, wideIndices=1)
        query = '&'.join(f'{key}={value}' for key, value in arguments.items())
        process = subprocess.run([str(app), '--verify', f'--query={query}'], cwd=root, text=True, capture_output=True, timeout=90)
        if process.returncode:
            raise RuntimeError(f'{name}: {process.stdout}\n{process.stderr}')
        for line in process.stdout.splitlines():
            if line.startswith('Ocean diagnostics: '):
                diagnostics = json.loads(line.removeprefix('Ocean diagnostics: '))
        assert diagnostics and diagnostics['fusedMips'] == (not legacy), 'Unexpected mip generation path'
        assert diagnostics and diagnostics['indexBits'] == (32 if legacy or name == 'index_fallback' else 16)
        captures.append(path.read_bytes())
        displays.append(Path(str(path)+".bgra8").read_bytes())
        assert diagnostics['sharedCubic'] == (True if args.fused_evolution or args.empty_foam_lighting else not baseline)
        if args.empty_foam_lighting: assert diagnostics['skipEmptyFoamLighting'] == (not baseline)
        expected_evolution = not (legacy or args.fused_evolution and baseline)
        assert diagnostics['fusedEvolution'] == expected_evolution
        assert diagnostics['spectrumBufferBytes'] == (0 if expected_evolution else 12*1024*1024)
        assert diagnostics['skipCloudOctaves'] == (not legacy)
        assert diagnostics['packedJacobian'] == (not legacy)
        mip_bytes,verified_jacobians = canonical_mips(Path(str(path)+".mips").read_bytes(),diagnostics['packedJacobian'])
        mips.append(mip_bytes)
    if captures[0] != captures[1]:
        changed, maximum = 0, 0.0
        for (a,), (b,) in zip(struct.iter_unpack('<e', captures[0]), struct.iter_unpack('<e', captures[1])):
            if a != b:
                changed += 1
                maximum = max(maximum, abs(a-b))
        raise AssertionError(f'{name}: {changed} changed HDR values; maximum error {maximum}')
    if mips[0] != mips[1]:
        changed = sum(a != b for a,b in zip(mips[0],mips[1]))
        raise AssertionError(f'{name}: {changed} changed canonical wave/foam mip bytes')
    if displays[0] != displays[1]:
        changed = sum(a != b for a,b in zip(displays[0], displays[1]))
        raise AssertionError(f'{name}: {changed} changed final display bytes')
    assert diagnostics and not diagnostics['errors']
    if 'renderWidth' in settings:
        assert abs(diagnostics['width']/diagnostics['height']-settings['renderWidth']/settings['renderHeight']) < 0.003
    result = {'case': name, 'width': diagnostics['width'], 'height': diagnostics['height'], 'triangles': diagnostics['triangles'], 'indexBits': diagnostics['indexBits'], 'indexBytes': diagnostics['indexBytes'], 'physicalGuard':diagnostics['physicalGuard'],'guardBoundsVerified':diagnostics['guardBoundsVerified'], 'fusedMips':diagnostics['fusedMips'],'mipmapRounding':diagnostics['mipmapRounding'], 'comparedHalfFloatValues': len(captures[0]) // 2, 'changedValues': 0, 'comparedDisplayBytes':len(displays[0]), 'changedDisplayBytes':0, 'fusedEvolution':diagnostics['fusedEvolution'],'spectrumBufferBytes':diagnostics['spectrumBufferBytes'],'sharedCubic':diagnostics['sharedCubic'],'skipCloudOctaves':diagnostics['skipCloudOctaves'],'packedJacobian':diagnostics['packedJacobian'],'packedJacobianHalfFloatsVerified':verified_jacobians,'comparedMipBytes':len(mips[0]),'changedMipBytes':0}
    results.append(result)
    print(json.dumps(result), flush=True)
(output / 'report.json').write_text(json.dumps({'passed': True, 'cases': results}, indent=2) + '\n')
print('PASS: all existing wave/foam mip channels, packed Jacobians, HDR values and final display bytes match the reference exactly.', flush=True)
