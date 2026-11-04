#!/usr/bin/env python3
"""Check portable entry-point links and required packaged shader resources."""
import hashlib,json,re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'macos/Shaders/manifest.json').read_text())
errors=[]
for name in manifest:
 if not (root/'macos/Shaders'/f'{name}.metal').is_file():errors.append(f'Missing shader: {name}')
for name in ['milkyway.r11g11b10f','metadata.json','CREDITS.md']:
 if not (root/'macos/Assets/Galaxy'/name).is_file():errors.append(f'Missing galaxy resource: {name}')
metadata=json.loads((root/'macos/Assets/Galaxy/metadata.json').read_text())
asset=(root/'macos/Assets/Galaxy/milkyway.r11g11b10f').read_bytes()
if len(asset)!=metadata['bytes'] or hashlib.sha256(asset).hexdigest()!=metadata['sha256']:
 errors.append('Packed galaxy bytes/checksum differ from provenance metadata')
files=['README.md','docs/README.md','docs/handoff.md','docs/architecture.md','docs/testing.md','docs/validation-2026-11-04.md']
for name in files:
 p=root/name
 if not p.is_file():errors.append(f'Missing guide: {name}');continue
 for target in re.findall(r'\]\(([^)]+)\)',p.read_text()):
  if re.match(r'[a-z]+:|#|/',target):continue
  target=target.split('#')[0]
  if target and not (p.parent/target).exists():errors.append(f'{name}: broken link {target}')
if errors:raise SystemExit('\n'.join(errors))
print(f'PASS: {len(manifest)} shader entries, galaxy resources and {len(files)} maintained guides')
