#!/usr/bin/env python3
"""Apply the supplied CPU support model to the current native bloom configuration.

This is a dependency-envelope experiment, not a GPU benchmark or culling mask.
It does not measure macOS opacity or model GPU UV interpolation roundoff.
"""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import sys
import numpy as np

root=Path(__file__).resolve().parents[2]
reference=root/'research/2026-10-30-ocean/prototypes/demand_planner.py'
spec=importlib.util.spec_from_file_location('ocean_research_demand',reference)
model=importlib.util.module_from_spec(spec);sys.modules[spec.name]=model;spec.loader.exec_module(model)
parser=argparse.ArgumentParser()
parser.add_argument('--width',type=int,default=1280)
parser.add_argument('--height',type=int,default=800)
parser.add_argument('--output',type=Path,default=root/'docs/research-native-bloom-2026-10-30.json')
args=parser.parse_args()
if min(args.width,args.height)<1 or args.width*args.height>8_000_000: parser.error('positive dimensions, at most 8M CPU model pixels')
renderer=root/'macos/OceanRenderer.swift'
levels=int(re.search(r'bloomLevels\s*=\s*(\d+)',renderer.read_text()).group(1))
down=root/'macos/Shaders/BLOOM_DOWN.metal';up=root/'macos/Shaders/BLOOM_UP.metal';composite=root/'macos/Shaders/COMPOSITE.metal'
assert len(re.findall(r'= tap\(',down.read_text()))==13
assert len(re.findall(r'= tap\(',up.read_text()))==9
assert 'bloom.sample' in composite.read_text() and '* 0.125' in composite.read_text()
w,h,tile=args.width,args.height,32
border=min(64,w/4,h/4)
center=model.Rect(border,border,w-border,h-border)
cases=[('all_visible',[],False),('confirmed_opaque_center',[model.OpaqueRegion(center,True)],False),
 ('left_quarter',[model.OpaqueRegion(model.Rect(w/4,0,w,h),True)],False),
 ('top_strip',[model.OpaqueRegion(model.Rect(0,min(160,h/2),w,h),True)],False),
 ('unknown_opacity',[model.OpaqueRegion(center,False)],False),('authoritatively_hidden',[],True)]
results=[]
for name,regions,hidden in cases:
    visible=model.tile_pixels(model.visible_tiles(w,h,tile,regions,fully_occluded=hidden),tile,w,h)
    support={}
    for count in sorted({4,levels,8}):
        if not visible.any() or visible.all(): required=visible
        else: required=model.bloom_demand(visible,levels=count)['hdr']
        support[str(count)]={'requiredHDRPixels':int(required.sum()),'requiredHDRFraction':float(required.mean())}
    # Idealized whole-window evidence for a 4x3 mosaic, not 32-pixel opacity data.
    mosaic=np.ones((h,w),dtype=bool);active=0
    trusted=[r.rect for r in regions if r.confirmed_opaque and not r.moving and 0<=r.age_seconds<=0.25]
    for row in range(3):
        y0=math.floor(row*h/3+0.5);y1=math.floor((row+1)*h/3+0.5)
        for column in range(4):
            x0=math.floor(column*w/4+0.5);x1=math.floor((column+1)*w/4+0.5)
            if x1<=x0 or y1<=y0: continue
            box=model.Rect(x0,y0,x1,y1)
            covered=hidden or model.union_area(trusted,box)>=box.area-1e-9
            mosaic[y0:y1,x0:x1]=not covered
            active+=int(not covered)
    mosaic_required=mosaic if not mosaic.any() or mosaic.all() else model.bloom_demand(mosaic,levels=levels)['hdr']
    mosaic_result={'visibleTileCount':active,'visibleOutputFraction':float(mosaic.mean()),'nativeBloomHDRSupportFraction':float(mosaic_required.mean()),
        'evidence':'Ideal whole-tile classification against synthetic proven opaque regions. Actual macOS per-tile behavior has not been measured.'}
    result={'mosaic4x3':mosaic_result,'scenario':name,'visiblePixels':int(visible.sum()),'visibleFraction':float(visible.mean()),'supportByBloomLevels':support}
    results.append(result);print(json.dumps(result),flush=True)
report={'evidence':'CPU mathematical support model only. Not an image-quality, GPU, power or OS-visibility result.',
 'sourceSnapshot':'current local native renderer','width':w,'height':h,'planningTile':tile,
 'nativeBloomLevels':levels,'nativeBloomExtents':[[max(1,w>>(i+1)),max(1,h>>(i+1))] for i in range(levels)],
 'compositeBloomScale':0.125,'firstDownsampleUsesNonlinearKarisWeights':True,
 'candidateSplit':{'localLevelCount':4,'firstGlobalLevelIndex':4,'globalProxyExtent':[max(1,w>>5),max(1,h>>5)],
    'status':'Unimplemented appearance approximation. Direct coarse shading does not equal filtered detailed HDR; glint energy and nonlinear Karis weighting require validation.'},
 'scenarios':results,
 'limitations':['Only already-proven opaque synthetic regions may remove demand. Unknown opacity stays visible.',
    'Bilinear support includes zero-weight neighbors at exact mathematical centers, but GPU interpolation/UV roundoff is not simulated. Production masks need conservative numerical guards and GPU impulse validation.',
    '4-level and split bloom are different filters/representations, not bit-identical performance optimizations.',
    'Keep the native 0.125 composite scale when isolating another change; altering normalization is a separate appearance change.',
    'All-hidden demand is zero; no partly visible surface is treated as fully hidden.'],
 'sources':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [renderer,down,up,composite,reference]}}
args.output.parent.mkdir(parents=True,exist_ok=True)
args.output.write_text(json.dumps(report,indent=2)+'\n')
