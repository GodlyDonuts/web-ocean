#!/bin/zsh
# ABI canary only: creates no windows and never registers/selects a wallpaper.
set -eu
cd "$(dirname "$0")/../.."
if [[ "$(sw_vers -productVersion | cut -d. -f1)" -lt 26 ]]; then
  echo "SKIP: native wallpaper runtime requires macOS 26"
  exit 0
fi
probe_path="$PWD/macos/build/native-preflight.app"
mkdir -p "$probe_path/Contents/MacOS" "$probe_path/Contents/Resources" macos/build/native-preflight
cp macos/WallpaperExtension/OceanFallback.png "$probe_path/Contents/Resources/"
python3 - <<'PY'
import plistlib
from pathlib import Path
Path('macos/build/native-preflight.app/Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'preflight','CFBundleIdentifier':'local.wallpaper.ocean.preflight','CFBundlePackageType':'APPL'}))
PY
xcrun clang -fobjc-arc -c macos/WallpaperExtension/WallpaperBridge.m -o macos/build/native-preflight/WallpaperBridge.o
xcrun swiftc -parse-as-library -import-objc-header macos/WallpaperExtension/WallpaperProtocols.h \
 macos/Tests/NativeWallpaperABITests.swift macos/WallpaperExtension/CodableShims.swift macos/WallpaperExtension/SettingsProvider.swift macos/build/native-preflight/WallpaperBridge.o \
 -framework AppKit -framework QuartzCore -framework IOSurface -o "$probe_path/Contents/MacOS/preflight"
"$probe_path/Contents/MacOS/preflight"
python3 - <<'PY'
import re,subprocess
p='macos/build/Ocean.app/Contents/PlugIns/OceanLiveWallpaper.appex/Contents/MacOS/OceanLiveWallpaper'
loads=subprocess.check_output(['otool','-l',p],text=True)
entry=int(re.search(r'cmd LC_MAIN\n.*?entryoff (\d+)',loads,re.S)[1])
base=int(re.search(r'segname __TEXT\n.*?vmaddr (0x[0-9a-f]+)',loads,re.S)[1],16)
symbols=subprocess.check_output(['nm',p],text=True)
main=int(re.search(r'^([0-9a-f]+) T _main$',symbols,re.M)[1],16)
assert '_NSExtensionMain' in symbols and entry != main-base,'Use the NSExtensionMain bootstrap, not Swift main as the executable entry'
print('PASS: native extension bootstrap differs from the Swift registration entry')
PY
