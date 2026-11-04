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
         column: Int, rowFromTop: Int, frame: NSRect, layout: Layout, labels: Bool) {
        self.displayID = displayID
        self.displayName = screen.localizedName
        self.column = column
        self.rowFromTop = rowFromTop
        self.frame = frame
        self.screenFrame = screen.frame
        self.backingScale = screen.backingScaleFactor
        self.key = "\(displayID):\(column):\(rowFromTop)"

        // AppKit's global origin is bottom-left on the primary screen. Quartz's
        // global display origin is top-left. Mapping through THIS screen avoids
        // assuming equal display scale factors or positive secondary origins.
        let cgDisplay = CGDisplayBounds(displayID)
        let sx = cgDisplay.width / screen.frame.width
        let sy = cgDisplay.height / screen.frame.height
        cgFrame = CGRect(
            x: cgDisplay.minX + (frame.minX - screen.frame.minX) * sx,
            y: cgDisplay.minY + (screen.frame.maxY - frame.maxY) * sy,
            width: frame.width * sx, height: frame.height * sy
        )

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
    private var labels = true
    private var transitionCount = 0
    private var generation = 0
    private let startUptime = ProcessInfo.processInfo.systemUptime
    private let dates = ISO8601DateFormatter()

    init(layout: Layout) {
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
            let scale = screen.backingScaleFactor
            let widthPixels = (screen.frame.width * scale).rounded()
            let heightPixels = (screen.frame.height * scale).rounded()
            for row in 0..<layout.rows {
                for column in 0..<layout.columns {
                    // Shared rounded boundaries avoid one-pixel seams between tiles.
                    let x0 = (CGFloat(column) * widthPixels / CGFloat(layout.columns)).rounded() / scale
                    let x1 = (CGFloat(column + 1) * widthPixels / CGFloat(layout.columns)).rounded() / scale
                    let y0 = (CGFloat(row) * heightPixels / CGFloat(layout.rows)).rounded() / scale
                    let y1 = (CGFloat(row + 1) * heightPixels / CGFloat(layout.rows)).rounded() / scale
                    let frame = NSRect(x: screen.frame.minX + x0,
                                       y: screen.frame.maxY - y1,
                                       width: x1 - x0, height: y1 - y0)
                    guard frame.width > 0, frame.height > 0 else { continue }
                    let tile = Tile(screen: screen, displayID: displayID, index: index,
                                    column: column, rowFromTop: row, frame: frame,
                                    layout: layout, labels: labels)
                    tiles.append(tile)
                    tileByWindow[ObjectIdentifier(tile.window)] = tile
                    tile.window.delegate = self
                    tile.window.orderFrontRegardless()
                }
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
        log("aggregate", ["reason": reason, "transitionCount": transitionCount,
                          "displays": displays])
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
        // This is context, not an assumption that activation equals occlusion.
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
        if CommandLine.arguments.contains("--help") {
            print("Usage: OcclusionProbe [--single | --tiled]\nDefault: 4 × 3 windows per display. Switch layouts or quit using the ◫ menu.\nJSON Lines are written to stdout. No GPU benchmark is performed.")
            return
        }
        let initial: Layout = CommandLine.arguments.contains("--single") ? .single : .tiled
        let app = NSApplication.shared
        let delegate = ProbeDelegate(layout: initial)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
