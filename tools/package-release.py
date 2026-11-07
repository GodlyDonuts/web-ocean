#!/usr/bin/env python3
"""Build a self-contained GitHub DMG; unsigned betas are explicitly opt-in."""
import argparse,hashlib,json,plistlib,re,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def run(*args):
    return subprocess.run([str(a) for a in args],check=True,capture_output=True,text=True).stdout

def validate_app(app):
    info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier')!='local.wallpaper.ocean':raise ValueError('Not an Ocean app bundle')
    if 'arm64' not in run('lipo','-archs',app/'Contents/MacOS/Ocean'):raise ValueError('Apple silicon executable is required')
    for rel in ['Resources/Help.html','Resources/Ocean.icns','Resources/Licenses/Ocean-LICENSE','Resources/Assets/Galaxy/milkyway.r11g11b10f','PlugIns/OceanLiveWallpaper.appex/Contents/MacOS/OceanLiveWallpaper']:
        if not (app/'Contents'/rel).is_file():raise ValueError('Missing bundled file: '+rel)
    for rel in ['Resources/Ocean.saver','PlugIns/OceanLiveWallpaper.appex']:
        nested=plistlib.loads((app/'Contents'/rel/'Contents/Info.plist').read_bytes())
        if (nested['CFBundleShortVersionString'],nested['CFBundleVersion'])!=(info['CFBundleShortVersionString'],info['CFBundleVersion']):raise ValueError('Bundle versions disagree')
    run('codesign','--verify','--strict','--deep',app)
    return info

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--app',type=Path,default=ROOT/'macos/build/Ocean.app')
    p.add_argument('--output',type=Path,default=ROOT/'macos/build/releases')
    p.add_argument('--tag',required=True)
    p.add_argument('--unsigned-beta',action='store_true')
    p.add_argument('--identity',help='Optional future Developer ID Application identity')
    p.add_argument('--notary-profile',help='Existing notarytool keychain profile; no credentials are stored here')
    p.add_argument('--allow-dirty',action='store_true',help='Local package tests only; never used by release CI')
    args=p.parse_args()
    if not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?',args.tag):p.error('Use vX.Y.Z or vX.Y.Z-beta.N')
    if args.unsigned_beta:
        if '-beta.' not in args.tag or args.identity or args.notary_profile:p.error('Unsigned packages must be beta tags, without signing credentials')
    elif not args.identity or not args.identity.startswith('Developer ID Application:') or not args.notary_profile:
        p.error('A stable release requires Developer ID Application signing and a notarytool profile; use --unsigned-beta for GitHub previews')
    dirty=bool(run('git','-C',ROOT,'status','--porcelain').strip())
    if dirty and not args.allow_dirty:p.error('Commit source changes before packaging, or use --allow-dirty for a local test')
    info=validate_app(args.app)
    if args.tag.removeprefix('v').split('-')[0]!=info['CFBundleShortVersionString']:p.error('Tag version and app version disagree')
    manifest=args.app/'Contents/Resources/SourceManifest.sha256'
    if not manifest.exists():p.error('Build the app with the current build script first')
    for line in manifest.read_text().splitlines():
        digest,rel=line.split('  ',1)
        path=ROOT/rel
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=digest:p.error('Build inputs changed; rebuild before packaging: '+rel)
    args.output.mkdir(parents=True,exist_ok=True)
    basename='Ocean-'+args.tag.removeprefix('v')+'-arm64'
    dmg=args.output/(basename+'.dmg')
    with tempfile.TemporaryDirectory(prefix='Ocean-release-') as tmp:
        tmp=Path(tmp);volume=tmp/'volume';volume.mkdir()
        app=volume/'Ocean.app';run('ditto',args.app,app)
        # Public beta support is deliberately limited to the native-host OS.
        plist=app/'Contents/Info.plist';packaged=plistlib.loads(plist.read_bytes());packaged['LSMinimumSystemVersion']='26.0';plist.write_bytes(plistlib.dumps(packaged,sort_keys=False))
        (app/'Contents/Resources/ReleaseInfo.json').write_text(json.dumps({'tag':args.tag,'commit':run('git','-C',ROOT,'rev-parse','HEAD').strip(),'unsignedBeta':args.unsigned_beta,'dirtyLocalTest':dirty},indent=2)+'\n')
        identity=args.identity or '-'
        sign_flags=['--options','runtime']+(['--timestamp'] if args.identity else ['--timestamp=none'])
        for rel,entitlements in [('Contents/Resources/Ocean.saver',None),('Contents/PlugIns/OceanLiveWallpaper.appex',ROOT/'macos/WallpaperExtension/OceanWallpaper.entitlements'),('',None)]:
            command=['codesign','--force','--sign',identity,*sign_flags]
            if entitlements:command+=['--entitlements',entitlements]
            run(*command,app/rel)
        validate_app(app)
        def notarize(path):
            result=json.loads(run('xcrun','notarytool','submit',path,'--keychain-profile',args.notary_profile,'--wait','--output-format','json'))
            if result.get('status')!='Accepted':raise RuntimeError('Notarization did not accept the artifact: '+str(result.get('id')))
        if args.identity:
            archive=tmp/'Ocean.zip';run('ditto','-c','-k','--keepParent',app,archive);notarize(archive)
            run('xcrun','stapler','staple',app);run('xcrun','stapler','validate',app)
        (volume/'Applications').symlink_to('/Applications')
        shutil.copyfile(ROOT/'macos/Resources/Help.html',volume/'Read Me First.html')
        shutil.copyfile(ROOT/'LICENSE',volume/'License.txt')
        run('hdiutil','create','-ov','-format','UDZO','-volname','Ocean','-srcfolder',volume,'-o',dmg)
        if args.identity:
            run('codesign','--force','--sign',identity,'--timestamp',dmg);notarize(dmg)
            run('xcrun','stapler','staple',dmg);run('xcrun','stapler','validate',dmg)
        run('hdiutil','verify',dmg)
    digest=hashlib.sha256(dmg.read_bytes()).hexdigest()
    (args.output/(basename+'.sha256')).write_text(digest+'  '+dmg.name+'\n')
    record={'tag':args.tag,'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'commit':run('git','-C',ROOT,'rev-parse','HEAD').strip(),'architecture':'arm64','minimumMacOS':'26.0','unsignedBeta':args.unsigned_beta,'notarized':bool(args.identity),'dirtyLocalTest':dirty,'sha256':digest,'bytes':dmg.stat().st_size}
    (args.output/(basename+'.json')).write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps(record,indent=2));print(dmg)
if __name__=='__main__':
    try:main()
    except (ValueError,RuntimeError,subprocess.CalledProcessError) as e:
        raise SystemExit(str(e)+(('\n'+e.stderr[-3000:]) if isinstance(e,subprocess.CalledProcessError) else ''))
