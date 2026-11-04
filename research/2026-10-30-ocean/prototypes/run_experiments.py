"""Generate reproducible workload counts and figures; never GPU timings."""
from pathlib import Path
import json
import sys
import math

import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import ListedColormap

from demand_planner import (Rect, OpaqueRegion, visible_tiles, tile_pixels,
                           merge_tiles, bloom_demand, harmonic_interpolation_error,
                           derivative_response)

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / 'results'
FIGURES = ROOT / 'figures'
RESULTS.mkdir(exist_ok=True)
FIGURES.mkdir(exist_ok=True)

plt.rcParams.update({'font.family':'DejaVu Sans', 'font.size':10,
                     'axes.spines.top':False, 'axes.spines.right':False})

def visibility_experiments():
    w,h,tile = 1920,1080,32
    definitions = [
        ('Fully visible', [], False),
        ('Opaque center, 64 px border', [OpaqueRegion(Rect(64,64,w-64,h-64),True)], False),
        ('Left quarter visible', [OpaqueRegion(Rect(w//4,0,w,h),True)], False),
        ('Top 160 px visible', [OpaqueRegion(Rect(0,160,w,h),True)], False),
        ('Uncertain / transparent center', [OpaqueRegion(Rect(64,64,w-64,h-64),False)], False),
        ('OS reports fully occluded', [], True),
    ]
    rows=[]
    selected=None
    for name,regions,hidden in definitions:
        tiles=visible_tiles(w,h,tile,regions,fully_occluded=hidden)
        visible=tile_pixels(tiles,tile,w,h)
        if visible.all() or not visible.any():
            # These two endpoints are exact without evaluating filter supports.
            demand8=demand4=visible.copy()
        else:
            demand8=bloom_demand(visible,8)['hdr']
            demand4=bloom_demand(visible,4)['hdr']
        row={'scenario':name,'output_width':w,'output_height':h,'planning_tile':tile,
             'tile_conservative_visible_fraction':float(visible.mean()),
             'hdr_required_current_8_level_bloom_fraction':float(demand8.mean()),
             'hdr_required_4_level_bloom_fraction':float(demand4.mean()),
             'visible_tile_count':int(tiles.sum()),'total_tiles':int(tiles.size),
             'merged_scissor_rectangles':len(merge_tiles(tiles,tile,w,h))}
        rows.append(row)
        if name.startswith('Opaque center'):
            selected=(visible,demand8,demand4)
        print(json.dumps(row),flush=True)
    fig,axs=plt.subplots(1,3,figsize=(12.8,3.25),layout='constrained')
    titles=['Visible tile area','HDR needed: current 8-level bloom','HDR needed: 4-level bloom']
    for ax,m,title in zip(axs,selected,titles):
        ax.imshow(m,cmap=ListedColormap(['#e7eef2','#078c95']),vmin=0,vmax=1,
                  interpolation='nearest',extent=[0,w,h,0])
        ax.set_title(title+'\n'+f'{100*m.mean():.1f}% of full image',fontweight='bold')
        ax.set_xticks([]);ax.set_yticks([])
    fig.suptitle('Visible pixels are not the complete shading dependency\n'
                 '1920 x 1080, confirmed opaque center, 32 px planning tiles. Teal = required work.',
                 fontsize=13,fontweight='bold')
    fig.savefig(FIGURES/'visibility_bloom_dependencies.png',dpi=180)
    plt.close(fig)
    return rows


def temporal_experiments():
    bands=[(.211,1),(.486,2),(1.123,5)]
    rows=[harmonic_interpolation_error(f,r,512,257) for f,r in bands]
    rates=np.linspace(2,20,120)
    lin=[];cub=[]
    for samples_per_cycle in rates:
        r=harmonic_interpolation_error(1,float(samples_per_cycle),64,129)
        lin.append(r['linear_max_abs_error']*100)
        cub.append(r['hermite_max_abs_error']*100)
    fig,ax=plt.subplots(figsize=(7.6,4.5),layout='constrained')
    ax.semilogy(rates,lin,label='Linear interpolation',color='#d47732',lw=2)
    ax.semilogy(rates,cub,label='Cubic Hermite + exact endpoint velocity',color='#078c95',lw=2)
    ax.axhline(2,color='#667883',ls='--',lw=1,label='2% unit-amplitude error')
    ax.set_xlabel('Simulation endpoint updates per wave cycle')
    ax.set_ylabel('Maximum absolute error (% of wave amplitude)')
    ax.set_title('Slow wave bands can be reconstructed between sparse updates',fontweight='bold')
    ax.grid(alpha=.18,which='both');ax.legend(fontsize=8)
    fig.savefig(FIGURES/'temporal_reconstruction_error.png',dpi=180)
    plt.close(fig)
    return rows


def spectrum_transition():
    rng=np.random.default_rng(20261030)
    n=1_000_000
    z0=(rng.standard_normal(n)+1j*rng.standard_normal(n))/math.sqrt(2)
    z1=(rng.standard_normal(n)+1j*rng.standard_normal(n))/math.sqrt(2)
    # Two target energies 1 and 4; midpoint target is 2.5.
    independent=.5*z0+.5*2*z1
    coherent_amplitude=(.5*1+.5*2)*z0
    coherent_energy=math.sqrt(2.5)*z0
    return {'target_midpoint_energy':2.5,'sample_count':n,'seed':20261030,
            'independent_surface_crossfade_measured_energy':float(np.mean(abs(independent)**2)),
            'same_phase_amplitude_blend_measured_energy':float(np.mean(abs(coherent_amplitude)**2)),
            'same_phase_energy_blend_measured_energy':float(np.mean(abs(coherent_energy)**2)),
            'interpretation':'CPU Monte Carlo of complex coefficients, not an ocean-image or GPU benchmark'}


if __name__=='__main__':
    output={'status':'CPU mathematical/reference experiments only; no GPU or macOS measurements',
            'source_commit':'8739f0793f84b96cb87a21558a117e1714184ad7',
            'visibility':visibility_experiments(),
            'temporal_reconstruction':temporal_experiments(),
            'weather_spectrum_transition':spectrum_transition(),
            'derivative_response':[
                {'grid':n,'maximum_frequency_bin':32,'order':o,
                 'amplitude_error':1-derivative_response(32/n,o)}
                for n in (256,128) for o in (4,6)]}
    (RESULTS/'reference_experiments.json').write_text(json.dumps(output,indent=2)+'\n')
    print(json.dumps({'temporal_reconstruction':output['temporal_reconstruction'],
                      'weather_spectrum_transition':output['weather_spectrum_transition'],
                      'derivative_response':output['derivative_response']},indent=2))
