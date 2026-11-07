#!/usr/bin/env python3
"""Release-mode rejection tests; never signs, mounts or uploads anything."""
import subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
cases=[
 (['--tag','v0.3.0','--unsigned-beta'],'Unsigned packages must be beta'),
 (['--tag','v0.3.0-beta.1'],'A stable release requires Developer ID'),
 (['--tag','v0.3.0-beta.1','--unsigned-beta','--identity','Apple Development: Test'],'Unsigned packages must be beta'),
 (['--tag','v0.3.0','--identity','Apple Development: Test','--notary-profile','unused'],'A stable release requires Developer ID'),
 (['--tag','v0.3.0-beta.1; touch /tmp/not-a-tag','--unsigned-beta'],'Use vX.Y.Z'),
]
for args,message in cases:
 p=subprocess.run([sys.executable,str(root/'tools/package-release.py'),*args],capture_output=True,text=True)
 assert p.returncode!=0 and message in p.stderr,(args,p.stdout,p.stderr)
print('PASS: unsigned/stable separation, invalid identities, beta-only opt-in and hostile tag rejection; no signing or OS writes')
