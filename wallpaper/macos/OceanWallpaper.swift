import AppKit
import CoreGraphics
import WebKit

// Deliberately small native host: AppKit window placement + power policy.
// The ocean itself stays in the existing WebGPU renderer.
private enum Mode: String, CaseIterable {
    case automatic, economy, balanced, quality

    var title: String {
        switch self {
        case .automatic: "Automatic (recommended)"
        case .economy: "Economy"
        case .balanced: "Balanced"
        case .quality: "Quality"
        }
    }
}

private struct Budget {
    let fps: Int
    let pixelLimit: Int
}

private final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class OceanSurface: NSObject, WKNavigationDelegate {
    let window: DesktopWindow
    private let webView: WKWebView
    private var wantedPause: Bool
    private let fps: Int

    init(screen: NSScreen, html: URL, governor: String, budget: Budget, paused: Bool) {
        self.fps = budget.fps
        self.wantedPause = paused

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.addUserScript(
            WKUserScript(
                source: governor,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: .page
            )
        )

        let view = WKWebView(frame: NSRect(origin: .zero, size: screen.frame.size),
                             configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.autoresizingMask = [.width, .height]
        view.allowsBackForwardNavigationGestures = false
        self.webView = view

        let frame = screen.frame
        let win = DesktopWindow(contentRect: frame, styleMask: [.borderless],
                                backing: .buffered, defer: false, screen: screen)
        win.isReleasedWhenClosed = false
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.ignoresMouseEvents = true
        win.isOpaque = true
        win.backgroundColor = .black
        win.hasShadow = false
        win.contentView = view
        self.window = win

        super.init()
        view.navigationDelegate = self

        // Explicit pixel budget, independent of Retina backing scale. The
        // existing renderer supports w/h and otherwise allocates full-resolution
        // 4x-MSAA textures; capping actual pixels is much cheaper than CSS scale.
        let physicalW = max(1.0, Double(frame.width * screen.backingScaleFactor))
        let physicalH = max(1.0, Double(frame.height * screen.backingScaleFactor))
        let factor = min(1.0, sqrt(Double(budget.pixelLimit) / (physicalW * physicalH)))
        let w = max(320, Int((physicalW * factor).rounded()))
        let h = max(200, Int((physicalH * factor).rounded()))

        var components = URLComponents(url: html, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "ui", value: "0"),
            URLQueryItem(name: "w", value: String(w)),
            URLQueryItem(name: "h", value: String(h))
        ]
        view.loadFileURL(components.url!, allowingReadAccessTo: html.deletingLastPathComponent())
        win.orderFrontRegardless()
    }

    func setPaused(_ value: Bool) {
        wantedPause = value
        let state = value ? "true" : "false"
        webView.evaluateJavaScript(
            "window.__oceanGovernor?.setPaused(\(state));",
            completionHandler: nil
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(
            "window.__oceanGovernor?.setFPS(\(fps));" +
            "window.__oceanGovernor?.setPaused(\(wantedPause ? "true" : "false"));",
            completionHandler: nil
        )
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        NSLog("Ocean wallpaper failed to load: %@", error.localizedDescription)
    }

    func close() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        window.orderOut(nil)
        window.close()
    }
}

@MainActor
private final class OceanAppDelegate: NSObject, NSApplicationDelegate {
    private var surfaces: [OceanSurface] = []
    private var statusItem: NSStatusItem!
    private var mode = Mode(rawValue: UserDefaults.standard.string(forKey: "ocean.mode") ?? "") ?? .automatic
    private var manuallyPaused = false
    private var systemPaused = false
    private var powerState = ""
    private var governorSource = ""
    private var htmlURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard let html = Bundle.main.url(forResource: "ocean", withExtension: "html"),
              let js = Bundle.main.url(forResource: "FrameGovernor", withExtension: "js"),
              let source = try? String(contentsOf: js, encoding: .utf8) else {
            NSLog("Missing bundled ocean.html or FrameGovernor.js")
            NSApp.terminate(nil)
            return
        }
        htmlURL = html
        governorSource = source

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let icon = NSImage(systemSymbolName: "water.waves",
                                  accessibilityDescription: "Ocean Wallpaper") {
                button.image = icon
            } else {
                button.title = "Ocean"
            }
        }
        buildMenu()
        installObservers()
        powerState = powerFingerprint()
        rebuildSurfaces()

        // No busy polling. Power/thermal policy checks happen once every 15 s.
        Timer.scheduledTimer(timeInterval: 15, target: self,
                             selector: #selector(refreshPower),
                             userInfo: nil, repeats: true)
    }

    private func budget(for displayIndex: Int) -> Budget {
        let p = ProcessInfo.processInfo
        let conserving = p.isLowPowerModeEnabled ||
                         p.thermalState == .serious || p.thermalState == .critical
        let base: Budget
        switch mode {
        case .automatic:
            base = conserving ? Budget(fps: 15, pixelLimit: 900_000)
                              : Budget(fps: 30, pixelLimit: 1_800_000)
        case .economy:
            base = Budget(fps: 15, pixelLimit: 850_000)
        case .balanced:
            base = Budget(fps: 30, pixelLimit: 1_800_000)
        case .quality:
            base = Budget(fps: 60, pixelLimit: 3_700_000)
        }
        // Each additional display is separately budgeted; don't multiply
        // desktop GPU cost by attaching external monitors.
        if displayIndex == 0 { return base }
        return Budget(fps: min(base.fps, 20),
                      pixelLimit: min(base.pixelLimit, 1_100_000))
    }

    private var shouldPause: Bool {
        manuallyPaused || systemPaused ||
        (mode == .automatic && ProcessInfo.processInfo.thermalState == .critical)
    }

    private func rebuildSurfaces() {
        guard let htmlURL else { return }
        surfaces.forEach { $0.close() }
        surfaces.removeAll()
        for (index, screen) in NSScreen.screens.enumerated() {
            surfaces.append(OceanSurface(screen: screen, html: htmlURL,
                                         governor: governorSource,
                                         budget: budget(for: index),
                                         paused: shouldPause))
        }
    }

    private func applyPause() {
        surfaces.forEach { $0.setPaused(shouldPause) }
        buildMenu()
    }

    private func buildMenu() {
        guard statusItem != nil else { return }
        let menu = NSMenu()
        let title = NSMenuItem(title: "Ocean Wallpaper", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        for itemMode in Mode.allCases {
            let item = NSMenuItem(title: itemMode.title,
                                  action: #selector(changeMode(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = itemMode.rawValue
            item.state = itemMode == mode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let pause = NSMenuItem(title: manuallyPaused ? "Resume" : "Pause",
                               action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        let quit = NSMenuItem(title: "Quit Ocean Wallpaper",
                              action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func installObservers() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(displayChanged),
                           name: NSApplication.didChangeScreenParametersNotification,
                           object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(suspend),
                              name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(resume),
                              name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(suspend),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(resume),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(suspend),
                              name: NSWorkspace.sessionDidResignActiveNotification,
                              object: nil)
        workspace.addObserver(self, selector: #selector(resume),
                              name: NSWorkspace.sessionDidBecomeActiveNotification,
                              object: nil)
    }

    private func powerFingerprint() -> String {
        let process = ProcessInfo.processInfo
        return "\(process.isLowPowerModeEnabled)-\(process.thermalState.rawValue)"
    }

    @objc private func changeMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let next = Mode(rawValue: raw) else { return }
        mode = next
        UserDefaults.standard.set(next.rawValue, forKey: "ocean.mode")
        rebuildSurfaces()
        buildMenu()
    }

    @objc private func togglePause() {
        manuallyPaused.toggle()
        applyPause()
    }

    @objc private func displayChanged(_ notification: Notification) {
        rebuildSurfaces()
    }

    @objc private func suspend(_ notification: Notification) {
        systemPaused = true
        applyPause()
    }

    @objc private func resume(_ notification: Notification) {
        systemPaused = false
        rebuildSurfaces() // Recover WebGPU resources after display sleep.
        applyPause()
    }

    @objc private func refreshPower() {
        let next = powerFingerprint()
        guard next != powerState else { return }
        powerState = next
        if mode == .automatic {
            rebuildSurfaces()
        }
        applyPause()
    }

    @objc private func quit() {
        surfaces.forEach { $0.close() }
        NSApp.terminate(nil)
    }
}

@main
private struct OceanWallpaper {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = OceanAppDelegate()
        app.delegate = delegate
        app.run()
    }
}
