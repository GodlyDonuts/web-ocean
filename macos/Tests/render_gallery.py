#!/usr/bin/env python3
"""Windowless gallery of the requested ocean, daylight and weather scene.

No historical captures are required. Failures in captures OR benchmarks fail CI.
Usage: python3 macos/Tests/render_gallery.py [scene ...]
"""
from datetime import datetime
import json, math, subprocess, sys
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[2]
app = root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
out = root/'macos/build/gallery'
def utc(s): return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()
ny = {'dayNight': 1, 'latitude': 40.7128, 'longitude': -74.006, 'timeZone': 'America/New_York'}
scenes = {
    'noon': {**ny, 'utc': utc('2026-10-30T16:40:00Z'), 'heading': 180},
    'golden_hour': {**ny, 'utc': utc('2026-10-30T21:35:00Z'), 'heading': 250},
    'sunset': {**ny, 'utc': utc('2026-10-30T21:45:00Z'), 'heading': 250},
    'twilight': {**ny, 'utc': utc('2026-10-30T22:20:00Z'), 'heading': 250},
    'moonlit_night': {**ny, 'utc': utc('2026-10-31T02:10:00Z'), 'heading': 60.0059176808, 'clouds': 0.15, 'veil': 0.1},
    'starry_night': {**ny, 'utc': utc('2026-06-21T04:00:00Z'), 'heading': 155, 'clouds': 0.12, 'veil': 0.05},
    'dark_night': {**ny, 'utc': utc('2026-11-10T04:00:00Z'), 'heading': 270},
    'rain': {**ny, 'utc': utc('2026-10-30T16:40:00Z'), 'storm': 0.4},
    'thunderstorm': {**ny, 'utc': utc('2026-10-30T16:40:00Z'), 'storm': 0.75},
    'hurricane_night': {**ny, 'utc': utc('2026-11-10T04:00:00Z'), 'heading': 270, 'storm': 1},
    'raised_storm_wave': {**ny, 'utc': utc('2026-11-10T04:00:00Z'), 'heading': 270, 'storm': 1, 'time': 60, 'fixedDt': 0},
    'portrait': {**ny, 'utc': utc('2026-10-30T21:45:00Z'), 'heading': 250, 'renderWidth': 759, 'renderHeight': 1349},
}
benchmarks = {name: scenes[name] for name in ['noon', 'dark_night', 'hurricane_night']}

def valid_background(d):
    return (d.get('offscreen') is True and d.get('windowCount') == 0 and d.get('activationPolicy') == 2
            and d.get('errors') == [] and d.get('solarCacheWrites') == 0)

def finite_positive(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v) and v > 0

def run_app(binary, mode, query, runner, timeout):
    return runner([str(binary), mode, '--query='+'&'.join(f'{k}={v}' for k,v in query.items())],
                  capture_output=True, text=True, timeout=timeout)

def capture(name, settings, directory=out, binary=app, runner=subprocess.run):
    directory.mkdir(parents=True, exist_ok=True)
    target=directory/f'{name}.rgba16f'; raw=Path(str(target)+'.bgra8'); png=directory/f'{name}.png'
    for p in [target, raw, png]: p.unlink(missing_ok=True)
    result={'scene':name,'ok':False}
    try:
        q={'fixedDt':0.0333333333,'time':30,'dump':target,**settings}
        p=run_app(binary,'--verify',q,runner,180)
        (directory/f'{name}.log').write_text(p.stdout+p.stderr)
        result['returncode']=p.returncode
        if p.returncode: raise ValueError(f'Capture exited {p.returncode}')
        lines=[s.removeprefix('Ocean diagnostics: ') for s in p.stdout.splitlines() if s.startswith('Ocean diagnostics: ')]
        if not lines: raise ValueError('Missing capture diagnostics')
        d=json.loads(lines[-1]);w,h=d.get('width'),d.get('height')
        if not valid_background(d): raise ValueError('Capture diagnostics failed background/error/cache checks')
        if not isinstance(w,int) or not isinstance(h,int) or w<=0 or h<=0: raise ValueError('Invalid capture dimensions')
        if not raw.is_file() or raw.stat().st_size!=w*h*4: raise ValueError('Missing or truncated display capture')
        Image.frombytes('RGBA',(w,h),raw.read_bytes(),'raw','BGRA').convert('RGB').save(png)
        result.update(ok=True,width=w,height=h,gpuMs=d.get('gpuMs'))
    except (ValueError,OSError,subprocess.SubprocessError) as e: result['error']=str(e)
    return result

def benchmark(name, settings, directory=out, binary=app, runner=subprocess.run):
    directory.mkdir(parents=True, exist_ok=True)
    report=directory/f'benchmark-{name}.json'
    # A failed run must never inherit an older successful report.
    report.unlink(missing_ok=True)
    result={'name':name,'ok':False}
    try:
        q={'fixedDt':0.0333333333,'frames':240,'report':report,**settings}
        p=run_app(binary,'--benchmark',q,runner,300)
        (directory/f'benchmark-{name}.log').write_text(p.stdout+p.stderr)
        result['returncode']=p.returncode
        if p.returncode: raise ValueError(f'Benchmark exited {p.returncode}')
        if not report.is_file(): raise ValueError('Missing benchmark report')
        d=json.loads(report.read_text())
        if not valid_background(d) or d.get('profiled') is not False: raise ValueError('Benchmark diagnostics failed')
        if not all(finite_positive(d.get(k)) for k in ['samples','gpuMedianMs','gpuMeanMs','gpuP95Ms']):
            raise ValueError('Missing or invalid timing samples')
        result.update(ok=True,diagnostics=d)
    except (ValueError,OSError,subprocess.SubprocessError) as e: result['error']=str(e)
    return result

def main(arguments):
    selected=arguments or list(scenes)
    unknown=set(selected)-scenes.keys()
    if unknown: raise SystemExit('Unknown scene(s): '+', '.join(sorted(unknown)))
    out.mkdir(parents=True, exist_ok=True)
    for p in [out/'gallery.json',out/'contact.png']: p.unlink(missing_ok=True)
    results=[]
    for name in selected:
        r=capture(name,scenes[name]);results.append(r);print(json.dumps(r),flush=True)
    pngs=[out/f'{r["scene"]}.png' for r in results if r['ok']]
    if pngs:
        sheet=Image.new('RGB',(640*3,400*((len(pngs)+2)//3)))
        for i,p in enumerate(pngs):
            with Image.open(p) as im: sheet.paste(im.resize((640,400)),((i%3)*640,(i//3)*400))
        sheet.save(out/'contact.png')
    timing={}
    for name,settings in benchmarks.items():
        r=benchmark(name,settings);timing[name]=r;print(json.dumps(r),flush=True)
    passed=all(r['ok'] for r in results) and all(r['ok'] for r in timing.values())
    (out/'gallery.json').write_text(json.dumps({'passed':passed,'scenes':results,'benchmarks':timing},indent=2)+'\n')
    # Keep failed captures for diagnosis; successful PNGs/reports remain available.
    for r in results:
        if r['ok']:
            for p in [out/f'{r["scene"]}.rgba16f',out/f'{r["scene"]}.rgba16f.bgra8']: p.unlink(missing_ok=True)
    return 0 if passed else 1

if __name__=='__main__': sys.exit(main(sys.argv[1:]))
