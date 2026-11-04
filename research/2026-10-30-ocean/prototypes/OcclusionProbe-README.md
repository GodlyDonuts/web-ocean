# Desktop tile occlusion diagnostic

This source tests whether a small mosaic of actual desktop-level windows gives
useful per-region occlusion notifications on the target Mac. It is an experiment,
not a validated renderer optimization. It has not been compiled or run on macOS
in the authoring environment.

## Run on the target Mac

```sh
bash build-occlusion-probe.sh
./build/OcclusionProbe.app/Contents/MacOS/OcclusionProbe --tiled > occlusion.jsonl
```

The diagnostic paints an opaque blue background behind desktop icons. It ignores
mouse input. Use the **◫** menu to switch between one window and a 4 × 3 grid per
display, show/hide labels, record a snapshot, or quit. Quitting removes its
windows and reveals the previous wallpaper. No settings or login items are
changed. Run only one probe instance at a time.

There is no WebView, Metal renderer, screen capture, other-app window enumeration,
or Accessibility API. The binary uses public AppKit/CoreGraphics APIs and does
not request screen-recording or accessibility permissions.

## What to test

Compare the two layouts under identical desktop activity:

1. Bare desktop; one opaque window covering part of it; two tiled opaque windows.
2. An opaque window slowly and rapidly moved/resized across tile boundaries.
3. A translucent terminal, translucent sidebar, rounded corners, and shadows.
4. Fullscreen applications, Space changes, Mission Control, Stage Manager,
   Show Desktop, and revealing a previously hidden desktop region.
5. Multiple displays, different Retina scales, hot-plug, sleep and wake.

Inspect `tile-occlusion-notification` and `aggregate` records. Every tile is
recorded immediately after creation and again on the next main-loop turn.
Snapshots include both AppKit global point coordinates and Quartz top-left
global coordinates. `column` and `rowFromTop` are zero-based.
They also log the actual AppKit window frame and whether it matches the planned
partition. If `allActualFramesMatchPlanned` is false, investigate AppKit frame
adjustment before treating the aggregate fraction as a display-area bound.

`visibleTileAreaUpperBoundFraction` counts the entire area of every tile whose
window has the `.visible` occlusion flag. It is an **upper bound**, not an exact
visible-pixel percentage. A partly covered tile is still fully counted. Window
occlusion notifications report state transitions, not changes in partial
coverage. The one-window layout should therefore remain at 1.0 whenever any
part of that display's wallpaper window is visible.

No polling or animation timer is used. Contextual activation/Space/sleep events
trigger state snapshots; these events do not imply that a window became visible
or hidden. Multiple occlusion notifications may briefly produce intermediate
aggregate states while a group of windows is changing visibility.

## Acceptance and limits

This prototype can establish whether tile windows at desktop level report useful
occlusion, how quickly events arrive, whether translucency is handled
conservatively, and whether window seams/Space behavior are acceptable.

It **cannot** establish GPU speedup, Metal drawable overhead, ocean quality,
power savings, or the net WindowServer cost of an animated implementation. The
static probe itself does no recurring render work. A production experiment must
compare one native shared ocean simulation with 1 versus 12 presentation windows,
then measure the whole system, including WindowServer, under the same workload.
Never instantiate one ocean simulation or one WebView per tile.

If this layout costs more energy or introduces desktop artifacts, retain a single
window per display and use OS full-window occlusion plus explicit best-effort
partial-visibility policies. Do not interpret this diagnostic as evidence that
macOS provides a public exact per-pixel occlusion region for arbitrary windows.

## API references

- [NSWindow.OcclusionState](https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.struct): an entire window is reported occluded when `.visible` is absent.
- [didChangeOcclusionStateNotification](https://developer.apple.com/documentation/appkit/nswindow/didchangeocclusionstatenotification): state changes do not describe changes to the partial occlusion region.
- [Apple energy guide, window visibility](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/WorkWhenVisible.html): per-window notifications are distinct from application visibility; a status item can keep an application considered visible.
- [CGDisplayBounds](https://developer.apple.com/documentation/coregraphics/cgdisplaybounds(_:)): Quartz global display bounds use the upper-left of the main display as the origin.

The mosaic strategy is an engineering hypothesis derived from those APIs. Apple
does not document it as an energy optimization or guarantee that it saves power.
