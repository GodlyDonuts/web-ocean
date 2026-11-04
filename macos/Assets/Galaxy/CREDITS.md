# Milky Way radiance asset

Source: [Deep Star Maps 2020, NASA SVS 4851](https://svs.gsfc.nasa.gov/4851/), `milkyway_2020_4k.exr` (celestial coordinates; bright Hipparcos/Tycho foreground omitted).

Credit: **NASA/Goddard Space Flight Center Scientific Visualization Studio. Gaia DR2: ESA/Gaia/DPAC.** Visualization: Ernie Wright (USRA).

Prepared for this application by area-filtering to 2048×1024, applying a linear exposure scale of 0.30 and packing to Metal R11G11B10 float. No NASA logos or constellation figures are included. The image supplies background radiance, not a claim of NASA endorsement.

See [NASA media-use guidance](https://www.nasa.gov/nasa-brand-center/images-and-media/). Provenance, checksums and encoding error are recorded in `metadata.json`. `tools/prepare-galaxy.py` regenerates the asset from the original EXR; app builds/runs do not download imagery or require Python/ffmpeg.
