#!/usr/bin/env python3
"""Prepare the NASA SVS linear EXR for native Metal. Build-time only; requires NumPy/ffmpeg."""
import argparse,hashlib,json,subprocess,tempfile
from pathlib import Path
import numpy as np
p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('--output',type=Path,default=Path('macos/Assets/Galaxy'));a=p.parse_args()
a.output.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory() as temp:
 raw=Path(temp)/'linear.gbrf32'
 subprocess.run(['ffmpeg','-v','error','-i',str(a.source),'-vf','scale=2048:1024:flags=area','-pix_fmt','gbrpf32le','-f','rawvideo',str(raw)],check=True)
 rgb=np.fromfile(raw,dtype='<f4').reshape(3,1024,2048)[[2,0,1]].transpose(1,2,0)
assert np.isfinite(rgb).all() and np.min(rgb)>=0
# Scene-referred artistic exposure, kept linear. No runtime tone-map decoding.
rgb=np.minimum(rgb*0.30,60000)
half=rgb.astype('<f2').view('<u2').astype(np.uint32)
r=(half[...,0]+8)>>4;g=(half[...,1]+8)>>4;b=(half[...,2]+16)>>5
packed=(r|(g<<11)|(b<<22)).astype('<u4')
asset=a.output/'milkyway.r11g11b10f';asset.write_bytes(packed.tobytes())
# Independent unpacking verifies finite HDR samples and quantization bounds.
def unpack(channel,mantissa):
 exp=channel>>mantissa;fraction=channel&((1<<mantissa)-1)
 return np.where(exp==0,fraction*2.0**(-14-mantissa),(1+fraction/float(1<<mantissa))*np.exp2(exp.astype(np.float64)-15))
decoded=np.stack([unpack(packed&2047,6),unpack((packed>>11)&2047,6),unpack((packed>>22)&1023,5)],axis=-1)
error=np.linalg.norm(decoded-rgb)/np.linalg.norm(rgb)
assert np.isfinite(decoded).all() and error<0.01
metadata={'sourceURL':'https://svs.gsfc.nasa.gov/vis/a000000/a004800/a004851/milkyway_2020_4k.exr','sourcePage':'https://svs.gsfc.nasa.gov/4851/','sourceSHA256':hashlib.sha256(a.source.read_bytes()).hexdigest(),'credit':'NASA/Goddard Space Flight Center Scientific Visualization Studio; Gaia DR2: ESA/Gaia/DPAC. Visualization: Ernie Wright.','description':'Milky Way background excluding bright Hipparcos/Tycho stars.','projection':'plate carree, ICRF/J2000; RA 0 at image centre, increasing left; north at top','width':2048,'height':1024,'metalPixelFormat':'rg11b10Float','byteOrder':'little endian','linearExposureScale':0.30,'bytes':asset.stat().st_size,'sha256':hashlib.sha256(asset.read_bytes()).hexdigest(),'relativeL2EncodingError':float(error),'runtimeDependencies':'None. Native Metal uploads packed linear data directly; ffmpeg/NumPy only needed to regenerate.'}
(a.output/'metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
print(json.dumps({'bytes':asset.stat().st_size,'encodingRelativeL2':float(error)}))
