# Native macOS Ocean Wallpaper (experimental)

A small native desktop host for the existing WebGPU ocean renderer.

**No Electron, Tauri, local web server, telemetry, or third-party runtime.**
The binary uses AppKit to place a window behind desktop icons and the system
WKWebView to execute the existing, bundled WebGPU page. That is **not** a native
Metal renderer; a future full Metal/wgpu port could eliminate the WebView.

## Requirements

- macOS 26 (Tahoe) or newer, ideally Apple Silicon.
- Xcode Command Line Tools (run xcode-select --install).
- WebGPU-capable system WebKit. Safari 26 added WebGPU, but this particular
  WKWebView + renderer combination has not been validated on a real Mac yet.

## Build and run

From the repository root:

~~~sh
bash wallpaper/macos/build.sh
open dist/OceanWallpaper.app
~~~

The script bundles the existing self-contained ocean.min.html from the
repository. If editing the ocean source, rebuild that HTML first with
npm install && npm run build. Node is *not* needed to build the native host
when the HTML bundle is current. No server is required at runtime.

The app lives in the menu bar. Use the water-waves icon to choose
Automatic, Economy, Balanced, Quality, Pause, or Quit. It opens one
noninteractive desktop-level window per connected monitor.

## Efficiency behavior

- Capped frame requests at 15, 30, or 60 FPS, depending on mode.
- Bounded *physical* GPU render area rather than rendering Retina full
  resolution blindly. Retina displays get appropriately budgeted textures.
- Automatic mode lowers FPS and resolution in macOS Low Power Mode or when
  high thermal pressure is reported.
- Each additional monitor gets a lower pixel and FPS budget.
- Zero scheduled frame callbacks on app-directed pause, sleep, display
  sleep, and session deactivation.
- Recreates display surfaces on screen changes and wake.
- Doesn't capture desktop mouse or keyboard inputs.
- No hidden process or login item.

Changes in render-resolution budget currently recreate the WebGPU page,
resetting its wave phase. A later optimization can keep simulation resources
alive while resizing output textures.

## Limitations and validation

**First implementation, not a validated release.** It has not been compiled
on macOS or measured for CPU/GPU utilization or battery drain yet. System
WebKit may differ from Chrome in WGSL compilation limits and background
rendering behavior. If the GPU adapter is unavailable, the original ocean
HTML reports an error.

Multi-display currently uses one WebGPU simulation per monitor. Future
optimization: shared render state or a true native wgpu/Metal engine.

Run the platform-independent scheduler tests:

~~~sh
node --test wallpaper/macos/FrameGovernor.test.mjs
~~~

Before tagging a release, test on an M1 8 GB Mac with AC/battery operation,
external monitors, fullscreen Spaces, sleep/wake and display hot-plug events.

## License and attribution

The ocean renderer remains the original project's work under its MIT
license. This native host adds a separate integration, not a claim to
authorship of the original sea simulation. Retain attribution when
redistributing modified versions.
