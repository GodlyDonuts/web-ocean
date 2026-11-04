#!/usr/bin/env python3
"""Windowless GPU gallery: renders representative scenes to PNG plus a benchmark.

Usage: python3 macos/Tests/render_gallery.py [scene ...]
Writes macos/build/gallery/*.png, contact.png and gallery.json.
"""
from datetime import datetime
import json, subprocess, sys
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[2]
app = root/'macos/build/Ocean.app/Contents/MacOS/Ocean'
out = root/'macos/build/gallery'; out.mkdir(parents=True, exist_ok=True)
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
    'arctic_night': {'dayNight': 1, 'latitude': 69.6, 'longitude': 18.9, 'timeZone': 'Europe/Oslo', 'utc': utc('2026-12-15T21:00:00Z'), 'heading': 0, 'clouds': 0.05},
    'thunderstorm': {'storm': 0.75, 'sunElev': 20},
    'hurricane_night': {**ny, 'storm': 1, 'utc': 1793417400},
    'after_rain': {'storm': 0.3, 'sunElev': 9, 'clouds': 0.5},
    'aurora_arctic': {'dayNight': 1, 'latitude': 69.6, 'longitude': 18.9, 'timeZone': 'Europe/Oslo', 'utc': utc('2026-12-15T21:00:00Z'), 'heading': 0, 'clouds': 0.05, 'aurora': 1, 'meteors': 0},
    'aurora_storm': {'dayNight': 1, 'latitude': 64.1, 'longitude': -21.9, 'timeZone': 'Atlantic/Reykjavik', 'utc': utc('2026-12-20T01:00:00Z'), 'heading': 330, 'clouds': 0.25, 'aurora': 2.5, 'meteors': 0},
    'meteor_shower_a': {**ny, 'utc': utc('2026-12-14T07:00:00Z'), 'heading': 120, 'clouds': 0.05, 'veil': 0.05, 'aurora': 0, 'meteors': 60, 'time': 31.2},
    'meteor_shower_b': {**ny, 'utc': utc('2026-12-14T07:00:00Z'), 'heading': 120, 'clouds': 0.05, 'veil': 0.05, 'aurora': 0, 'meteors': 60, 'time': 47.9},
    'aurora_max': {'dayNight': 1, 'latitude': 69.6, 'longitude': 18.9, 'timeZone': 'Europe/Oslo', 'utc': utc('2026-12-15T21:00:00Z'), 'heading': 200, 'clouds': 0.05, 'aurora': 4, 'meteors': 0},
    'bioluminescent_surf': {**ny, 'utc': utc('2026-11-10T04:00:00Z'), 'heading': 270, 'windSpeed': 13, 'bio': 1.5, 'aurora': 0},
    'sun_shafts': {'sunElev': 5, 'clouds': 0.7, 'veil': 0.2},
    'storm_breaking': {'storm': 0.45, 'sunElev': 7, 'clouds': 0.85},
    'ice_halo': {'sunElev': 12, 'clouds': 0.05, 'veil': 0.55},
    'moon_halo': {**ny, 'utc': utc('2026-10-31T02:10:00Z'), 'heading': 60.0059176808, 'clouds': 0.02, 'veil': 0.5},
    'everything_night': {'dayNight': 1, 'latitude': 66.0, 'longitude': -18.0, 'timeZone': 'Atlantic/Reykjavik', 'utc': utc('2026-12-14T02:00:00Z'), 'heading': 20, 'clouds': 0.1, 'windSpeed': 12, 'aurora': 1.6, 'meteors': 60, 'bio': 1.2},
}
selected = sys.argv[1:] or list(scenes)
results = []
for name in selected:
    target = out/f'{name}.rgba16f'
    q = {'fixedDt': 0.0333333333, 'time': 30, 'dump': target, **scenes[name]}
    p = subprocess.run([str(app), '--verify', '--query=' + '&'.join(f'{k}={v}' for k, v in q.items())],
                       capture_output=True, text=True, timeout=180)
    (out/f'{name}.log').write_text(p.stdout + p.stderr)
    diag = [s.removeprefix('Ocean diagnostics: ') for s in p.stdout.splitlines() if s.startswith('Ocean diagnostics: ')]
    d = json.loads(diag[-1]) if diag else {}
    w, h = d.get('width', 1280), d.get('height', 800)
    raw = Path(str(target) + '.bgra8')
    ok = p.returncode == 0 and raw.is_file()
    if ok:
        Image.frombytes('RGBA', (w, h), raw.read_bytes(), 'raw', 'BGRA').convert('RGB').save(out/f'{name}.png')
    results.append({'scene': name, 'ok': ok, 'returncode': p.returncode, 'width': w, 'height': h,
                    'gpuMs': d.get('gpuMs'), 'errors': d.get('errors'), 'tail': (p.stdout + p.stderr)[-1500:] if not ok else ''})
    print(json.dumps(results[-1]), flush=True)
pngs = [out/f'{r["scene"]}.png' for r in results if r['ok']]
if pngs:
    thumbs = [Image.open(p).resize((640, 400)) for p in pngs]
    cols = 3; rows = (len(thumbs) + cols - 1)//cols
    sheet = Image.new('RGB', (640*cols, 400*rows))
    for i, t in enumerate(thumbs): sheet.paste(t, ((i % cols)*640, (i//cols)*400))
    sheet.save(out/'contact.png')
night = {k: v for k, v in scenes['everything_night'].items() if k != 'time'}
benchmarks = {'default': {}, 'night_effects_off': {**night, 'aurora': 0, 'meteors': 0, 'bio': 0}, 'night_effects_on': night, 'shafts_off': {**scenes['sun_shafts'], 'shafts': 0}, 'shafts_on': scenes['sun_shafts']}
bench_results = {}
for label, extra in benchmarks.items():
    bench = out/f'benchmark-{label}.json'
    q = {'fixedDt': 0.0333333333, 'frames': 240, 'report': bench, **extra}
    p = subprocess.run([str(app), '--benchmark', '--query=' + '&'.join(f'{k}={v}' for k, v in q.items())], capture_output=True, text=True, timeout=300)
    (out/f'benchmark-{label}.log').write_text(p.stdout + p.stderr)
    bench_results[label] = json.loads(bench.read_text()) if bench.is_file() else None
    b = bench_results[label] or {}
    print(f"benchmark {label}: median {b.get('gpuMedianMs')} ms, p95 {b.get('gpuP95Ms')} ms")
(out/'gallery.json').write_text(json.dumps({'scenes': results, 'benchmarks': bench_results}, indent=2))
for r in results:
    for f in [out/f'{r["scene"]}.rgba16f', Path(str(out/f'{r["scene"]}.rgba16f') + '.bgra8')]: f.unlink(missing_ok=True)
sys.exit(0 if all(r['ok'] for r in results) else 1)
