#!/bin/zsh
set -eu
cd "$(dirname "$0")/../.."
# A loadable dylib can pass Bundle.load but isn't a proper screensaver plugin.
file macos/build/Ocean.saver/Contents/MacOS/OceanScreenSaver | /usr/bin/grep -Eq 'Mach-O.*bundle'
mkdir -p macos/build/unit
xcrun swiftc -parse-as-library macos/Tests/ScreenSaverLifecycleTests.swift -framework AppKit -framework ScreenSaver -o macos/build/unit/ScreenSaverLifecycleTests
macos/build/unit/ScreenSaverLifecycleTests "$PWD/macos/build/Ocean.saver"
