// Adapted from the user-supplied 2026-10-30 research kit; original retained under research/.
import AppKit
import CoreGraphics
import Foundation

// Diagnostic only. This intentionally paints opaque desktop-level windows.
// It does not render an ocean, use Metal, enumerate other apps, or capture pixels.
// Its area metric is an upper bound: a partly visible tile counts as fully visible.

private enum Layout: Int, CaseIterable {
    case single = 1
    case tiled = 12

    var columns: Int { self == .single ? 1 : 4 }
    var rows: Int { self == .single ? 1 : 3 }
    var title: String { self == .single ? "One window per display (1 × 1)" : "Twelve windows per display (4 × 3)" }
}

private func rectJSON(_ rect: CGRect) -> [String: Double] {
    ["x": Double(rect.origin.x), "y": Double(rect.origin.y),
     "width": Double(rect.width), "height": Double(rect.height)]
}

@MainActor
private final class DesktopProbeWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class ProbeView: NSView {
    let caption: String
    let color: NSColor
    var labelsEnabled = true

    init(frame: NSRect, caption: String, color: NSColor) {
        self.caption = caption
        self.color = color
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("Not used") }
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.fill()
        guard labelsEnabled else { return }
        NSColor.white.withAlphaComponent(0.30).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        border.lineWidth = 1
        border.stroke()
        let textRect = NSRect(x: 20, y: max(10, bounds.height - 100),
                              width: max(1, bounds.width - 40), height: 80)
        (caption as NSString).draw(in: textRect, withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.8)
        ])
    }
}

@MainActor
private final class Tile {
    let key: String
    let displayID: CGDirectDisplayID
    let displayName: String
    let column: Int
    let rowFromTop: Int
    let frame: NSRect
    let cgFrame: CGRect
    let screenFrame: NSRect
    let backingScale: CGFloat
    let window: DesktopProbeWindow
    let view: ProbeView
    var lastObservedVisible: Bool?

    init(screen: NSScreen, displayID: CGDirectDisplayID, index: Int,
         column: Int, rowFromTop: Int, placement: DisplayTilePlacement, layout: Layout, labels: Bool) {
        let frame = placement.appKitPoints
        self.displayID = displayID
        self.displayName = screen.localizedName
        self.column = column
        self.rowFromTop = rowFromTop
        self.frame = frame
        self.screenFrame = screen.frame
        self.backingScale = screen.backingScaleFactor
        self.key = "\(displayID):\(column):\(rowFromTop)"

        cgFrame = placement.quartz

        let tint = CGFloat((column + rowFromTop) % 2) * 0.018
        let color = NSColor(calibratedRed: 0.025 + tint, green: 0.13 + tint,
                            blue: 0.18 + tint, alpha: 1)
        let caption = "Occlusion diagnostic · display \(index + 1)\n" +
                      "tile \(column + 1),\(rowFromTop + 1) · \(layout.columns) × \(layout.rows)\n" +
                      "Quit from the ◫ menu"
        let probeView = ProbeView(frame: NSRect(origin: .zero, size: frame.size),
                                  caption: caption, color: color)
        probeView.labelsEnabled = labels
        probeView.autoresizingMask = [.width, .height]

        let probeWindow = DesktopProbeWindow(contentRect: frame, styleMask: [.borderless],
                                            backing: .buffered, defer: false, screen: screen)
        probeWindow.isReleasedWhenClosed = false
        probeWindow.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        probeWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        probeWindow.ignoresMouseEvents = true
        probeWindow.isOpaque = true
        probeWindow.hasShadow = false
        probeWindow.backgroundColor = color
        probeWindow.contentView = probeView
        probeWindow.title = "Ocean occlusion probe \(displayID):\(column):\(rowFromTop)"
        self.view = probeView
        self.window = probeWindow
    }

    var visible: Bool { window.occlusionState.contains(.visible) }
    var area: Double { Double(frame.width * frame.height) }

    func description() -> [String: Any] {
        ["tile": key, "displayID": displayID, "displayName": displayName,
         "column": column, "rowFromTop": rowFromTop,
         "windowNumber": window.windowNumber,
         "appKitGlobalFramePoints": rectJSON(frame),
         "actualAppKitGlobalFramePoints": rectJSON(window.frame),
         "actualFrameMatchesPlanned": NSEqualRects(window.frame, frame),
         "quartzGlobalFrame": rectJSON(cgFrame),
         "displayAppKitFramePoints": rectJSON(screenFrame),
         "backingScaleFactor": Double(backingScale),
         "nominalBackingPixelWidth": Double(frame.width * backingScale),
         "nominalBackingPixelHeight": Double(frame.height * backingScale),
         "occlusionVisible": visible,
         "orderedOnscreen": window.isVisible,
         "onActiveSpace": window.isOnActiveSpace]
    }
}

@MainActor
private final class ProbeDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var layout: Layout
    private var tiles: [Tile] = []
    private var tileByWindow: [ObjectIdentifier: Tile] = [:]
    private var statusItem: NSStatusItem!
    private var rebuilding = false
    private var suspension = SurfaceSuspensionState()
    private var labels = true
    private var transitionCount = 0
    private var generation = 0
    private let startUptime = ProcessInfo.processInfo.systemUptime
    private let dates = ISO8601DateFormatter()
    private let duration: TimeInterval

    init(layout: Layout, duration: TimeInterval) {
        self.duration = duration
        self.layout = layout
        super.init()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    private func log(_ event: String, _ fields: [String: Any] = [:]) {
        var object = fields
        object["event"] = event
        object["timestampUTC"] = dates.string(from: Date())
        object["elapsedMs"] = (ProcessInfo.processInfo.systemUptime - startUptime) * 1000
        object["layout"] = "\(layout.columns)x\(layout.rows)"
        object["generation"] = generation
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        FileHandle.standardOutput.write(Data(line.utf8))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "◫"
        statusItem.button?.toolTip = "Ocean occlusion diagnostic"
        makeMenu()
        installObservers()
        log("start", [
            "purpose": "Observe OS occlusion of actual opaque desktop windows",
            "gpuBenchmark": false, "usesScreenCapture": false,
            "enumeratesOtherAppWindows": false,
            "areaMetric": "upper bound from whole visible tiles, not exact visible pixels"
        ])
        rebuild(reason: "startup")
        if duration > 0 {
            Timer.scheduledTimer(withTimeInterval:duration,repeats:false) { _ in NSApp.terminate(nil) }
        }
    }

    private func makeMenu() {
        let menu = NSMenu()
        let heading = NSMenuItem(title: "Ocean occlusion diagnostic", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        for candidate in Layout.allCases {
            let item = NSMenuItem(title: candidate.title, action: #selector(changeLayout(_:)), keyEquivalent: "")
            item.target = self
            item.tag = candidate.rawValue
            item.state = candidate == layout ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let labelItem = NSMenuItem(title: "Show tile labels and borders", action: #selector(toggleLabels), keyEquivalent: "")
        labelItem.target = self
        labelItem.state = labels ? .on : .off
        menu.addItem(labelItem)
        let snapshot = NSMenuItem(title: "Log current state", action: #selector(snapshotNow), keyEquivalent: "l")
        snapshot.target = self
        menu.addItem(snapshot)
        let quit = NSMenuItem(title: "Quit diagnostic", action: #selector(quitNow), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func installObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.willSleepNotification,
                     NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self, selector: #selector(workspaceChanged(_:)), name: name, object: nil)
        }
    }

    private func closeTiles() {
        for tile in tiles {
            tile.window.delegate = nil
            tile.window.orderOut(nil)
            tile.window.close()
        }
        tileByWindow.removeAll()
        tiles.removeAll()
    }

    private func rebuild(reason: String) {
        rebuilding = true
        generation += 1
        closeTiles()
        for (index, screen) in NSScreen.screens.enumerated() {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let displayID = CGDirectDisplayID(number.uint32Value)
            guard let placement = try? DisplayTileLayout(appKitFrame:screen.frame,
                quartzFrame:CGDisplayBounds(displayID),backingScale:screen.backingScaleFactor,
                columns:layout.columns,rows:layout.rows) else {
                log("invalid-display-layout",["displayID":displayID]); continue
            }
            for cell in placement.tiles {
                let tile = Tile(screen:screen,displayID:displayID,index:index,
                    column:cell.column,rowFromTop:cell.rowFromTop,placement:cell,layout:layout,labels:labels)
                tiles.append(tile)
                tileByWindow[ObjectIdentifier(tile.window)] = tile
                tile.window.delegate = self
                tile.window.orderFrontRegardless()
            }
        }
        rebuilding = false
        logSnapshot(reason: reason + "-initial")
        let capturedGeneration = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == capturedGeneration else { return }
            self.logSnapshot(reason: reason + "-next-main-loop")
        }
    }

    private func logAggregate(reason: String) {
        let displayIDs = Set(tiles.map { $0.displayID }).sorted()
        var displays: [[String: Any]] = []
        for displayID in displayIDs {
            let group = tiles.filter { $0.displayID == displayID }
            let total = group.reduce(0.0) { $0 + $1.area }
            let visible = group.filter { $0.visible }
            let visibleArea = visible.reduce(0.0) { $0 + $1.area }
            displays.append([
                "displayID": displayID,
                "tileCount": group.count,
                "visibleTileCount": visible.count,
                "allActualFramesMatchPlanned": group.allSatisfy { NSEqualRects($0.window.frame, $0.frame) },
                "visibleTileAreaUpperBoundFraction": total > 0 ? visibleArea / total : 0,
                "allTilesFullyOccluded": visible.isEmpty
            ])
        }
        let requests = tiles.map { SurfaceDemandRequest(surfaceID:$0.key,worldID:"shared-ocean",
            visibility:$0.visible ? .visible : .occluded,framesPerSecond:30,requiredWaveBands:0x3f) }
        let demand = SharedSurfaceDemand.plan(requests,suspended:suspension.isSuspended)["shared-ocean"]
        log("aggregate", ["reason": reason, "transitionCount": transitionCount,
                          "displays": displays,"sharedRequestedHz":demand?.presentationHz ?? 0,
                          "sharedRequestedWaveBandHz":demand?.waveBandHz ?? [Int](repeating:0,count:6),
                          "metalCommandBuffersSubmitted":0])
    }

    private func logSnapshot(reason: String) {
        for tile in tiles {
            tile.lastObservedVisible = tile.visible
            var fields = tile.description()
            fields["reason"] = reason
            log("tile-snapshot", fields)
        }
        logAggregate(reason: reason)
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard !rebuilding, let window = notification.object as? NSWindow,
              let tile = tileByWindow[ObjectIdentifier(window)] else { return }
        let previous = tile.lastObservedVisible
        tile.lastObservedVisible = tile.visible
        transitionCount += 1
        var fields = tile.description()
        fields["previousOcclusionVisible"] = previous.map { $0 as Any } ?? NSNull()
        fields["transitionNumber"] = transitionCount
        log("tile-occlusion-notification", fields)
        logAggregate(reason: "occlusion-notification")
    }

    @objc private func changeLayout(_ sender: NSMenuItem) {
        guard let next = Layout(rawValue: sender.tag), next != layout else { return }
        layout = next
        rebuild(reason: "layout-change")
        makeMenu()
    }

    @objc private func toggleLabels() {
        labels.toggle()
        for tile in tiles {
            tile.view.labelsEnabled = labels
            tile.view.needsDisplay = true
        }
        makeMenu()
    }

    @objc private func snapshotNow() { logSnapshot(reason: "manual") }
    @objc private func quitNow() { NSApp.terminate(nil) }

    @objc private func screensChanged(_ notification: Notification) {
        rebuild(reason: "display-configuration-change")
    }

    @objc private func workspaceChanged(_ notification: Notification) {
        switch notification.name {
        case NSWorkspace.willSleepNotification: suspension.set(.systemSleep,active:true)
        case NSWorkspace.didWakeNotification: suspension.set(.systemSleep,active:false)
        case NSWorkspace.screensDidSleepNotification: suspension.set(.displaySleep,active:true)
        case NSWorkspace.screensDidWakeNotification: suspension.set(.displaySleep,active:false)
        case NSWorkspace.sessionDidResignActiveNotification: suspension.set(.inactiveSession,active:true)
        case NSWorkspace.sessionDidBecomeActiveNotification: suspension.set(.inactiveSession,active:false)
        default: break
        }
        // App activation alone does not establish tile occlusion.
        log("workspace-event", ["name": notification.name.rawValue])
        logSnapshot(reason: notification.name.rawValue)
    }

    func applicationWillTerminate(_ notification: Notification) {
        logAggregate(reason: "quit")
        log("stop")
        closeTiles()
    }
}

@main
private struct OcclusionProbe {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        let initial: Layout = arguments.contains("--single") ? .single : .tiled
        if arguments.contains("--describe-layout") {
            let app = NSApplication.shared
            app.setActivationPolicy(.prohibited)
            var displays: [[String:Any]] = []
            for screen in NSScreen.screens {
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
                let id = CGDirectDisplayID(number.uint32Value)
                do {
                    let layout = try DisplayTileLayout(appKitFrame:screen.frame,quartzFrame:CGDisplayBounds(id),
                        backingScale:screen.backingScaleFactor,columns:initial.columns,rows:initial.rows)
                    displays.append(["displayID":id,"name":screen.localizedName,"scale":Double(screen.backingScaleFactor),
                        "pixelWidth":layout.pixelWidth,"pixelHeight":layout.pixelHeight,
                        "tiles":layout.tiles.map { ["column":$0.column,"row":$0.rowFromTop,
                            "pixels":rectJSON($0.pixels),"appKitPoints":rectJSON($0.appKitPoints),"quartz":rectJSON($0.quartz)] }])
                } catch { fputs("Invalid screen layout: \(error)\n",stderr); exit(1) }
            }
            let report: [String:Any] = ["layout":"\(initial.columns)x\(initial.rows)","displays":displays,"windowCount":app.windows.count,
                "activationPolicy":app.activationPolicy().rawValue,"visibilityMeasured":false,"metalCommandBuffersSubmitted":0,
                "pixelCoordinateSpace":"nominal AppKit backing pixels, not panel-native hardware resolution"]
            let data = try! JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
            FileHandle.standardOutput.write(data); print("")
            precondition(app.windows.isEmpty)
            return
        }
        guard arguments.contains("--present"), !arguments.contains("--help") else {
            print("Usage: OcclusionProbe --describe-layout | --present [--single | --tiled] [--duration=SECONDS]\nDefault is windowless. Presentation requires --present, lasts 60 seconds by default, and can be stopped with the ◫ menu. --duration=0 disables automatic exit. This static diagnostic is not a GPU benchmark.")
            return
        }
        let rawDuration = arguments.first(where:{$0.hasPrefix("--duration=")}).map { String($0.dropFirst(11)) } ?? "60"
        guard let duration = Double(rawDuration),duration.isFinite,duration >= 0,duration <= 3600 else {
            fputs("duration must be finite and between 0 and 3600 seconds\n",stderr); exit(2)
        }
        let app = NSApplication.shared
        let delegate = ProbeDelegate(layout: initial,duration:duration)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
