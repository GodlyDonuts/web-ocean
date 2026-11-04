import AppKit
import IOKit.ps
import MetalKit
import ServiceManagement

enum OceanRunMode {
    static let offscreen = (CommandLine.arguments.contains("--verify") || CommandLine.arguments.contains("--benchmark"))
        && !CommandLine.arguments.contains("--windowed-test")
    // The installed product is a desktop wallpaper. `--preview` keeps the
    // resizable development window; automated windowed tests use it too.
    static let preview = !offscreen && (CommandLine.arguments.contains("--preview") || CommandLine.arguments.contains("--windowed-test"))
    static let wallpaper = !offscreen && !preview
}

// Borderless, click-through window at desktop level: below Finder icons,
// present on every Space, never key, never in Mission Control's window cycle.
final class WallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        isReleasedWhenClosed = false
        animationBehavior = .none
        setFrame(screen.frame, display: false)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct WallpaperSurface {
    let screen: NSScreen
    let window: NSWindow
    let view: MTKView
}

final class OceanApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var viewport: MTKView!
    private var device: MTLDevice?
    private var surfaces: [WallpaperSurface] = []
    private var renderer: OceanRenderer?
    private var suspension = SurfaceSuspensionState()
    private var automationTimer: Timer?
    private var followsWeather=true
    private var weatherProvider:WeatherProvider?
    private var weatherStatus:NSMenuItem?
    private var stormSlider:NSSlider?
    private var locationProvider: ObserverLocationProvider?
    private var daylightStatus: NSMenuItem?
    private var solarTimesItem: NSMenuItem?
    private var options: [String: String] = [:]
    // Wallpaper performance state.
    private var statusItem: NSStatusItem?
    private var performanceStatus: NSMenuItem?
    private var pauseItem: NSMenuItem?
    private var loginItem: NSMenuItem?
    private var rateItems: [NSMenuItem] = []
    private var qualityItems: [NSMenuItem] = []
    private var displayItems: [NSMenuItem] = []
    private var coverageTimer: Timer?
    private var visibleFraction: [CGDirectDisplayID: Double] = [:]
    private var onBattery = false
    private var lastPowerCheck = -Double.infinity
    private var decision = PerformanceDecision(framesPerSecond: 30, pixelBudget: PerformancePolicy.balancedBudget, reason: "full quality")
    private let defaults = UserDefaults.standard
    private var requestedFPS: Int { defaults.integer(forKey: "OceanFramesPerSecond") }
    private var requestedBudget: Double { let v = defaults.double(forKey: "OceanPixelBudget"); return v > 0 ? v : PerformancePolicy.balancedBudget }
    private var allDisplays: Bool { defaults.object(forKey: "OceanAllDisplays") as? Bool ?? true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--query=") }),
           let items = URLComponents(string: "?" + argument.dropFirst(8))?.queryItems {
            for item in items { options[item.name] = item.value }
        }
        if OceanRunMode.preview {
            let menu = NSMenu()
            let appItem = NSMenuItem()
            menu.addItem(appItem)
            let appMenu = NSMenu()
            appMenu.addItem(withTitle: "Quit Ocean", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            appItem.submenu = appMenu
            let viewItem = NSMenuItem()
            menu.addItem(viewItem)
            let viewMenu = NSMenu(title: "View")
            let fullscreen = NSMenuItem(title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            fullscreen.keyEquivalentModifierMask = [.command, .control]
            viewMenu.addItem(fullscreen)
            viewItem.submenu = viewMenu
            for item in environmentMenuItems() { menu.addItem(item) }
            NSApp.mainMenu = menu
        }

        guard let device = MTLCreateSystemDefaultDevice() else { showError("This Mac does not support Metal."); return }
        self.device = device
        func dimension(_ key: String, fallback: Double, minimum: Double) -> CGFloat {
            guard let number = Double(options[key] ?? ""), number.isFinite, number > 0 else { return CGFloat(fallback) }
            return CGFloat(max(minimum,min(8192,number)))
        }
        if OceanRunMode.wallpaper {
            buildSurfaces()
            viewport = surfaces.first?.view
        }
        if viewport == nil {
            viewport = makeView(frame: NSRect(x:0,y:0,width:dimension("width",fallback:1200,minimum:640),
                                              height:dimension("height",fallback:750,minimum:400)), device: device)
            viewport.framebufferOnly = !CommandLine.arguments.contains("--verify")
        }
        if OceanRunMode.preview {
            window = NSWindow(contentRect: viewport.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Ocean — Metal"
            window.delegate = self
            window.minSize = NSSize(width: 640, height: 400)
            window.backgroundColor = .black
            window.contentView = viewport
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.fullScreenPrimary]
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        if let fps = Int(options["fps"] ?? "") { viewport.preferredFramesPerSecond = max(1,min(60,fps)) }
        let diagnostics = CommandLine.arguments.contains("--diagnostics") || CommandLine.arguments.contains("--verify") || CommandLine.arguments.contains("--profile") || CommandLine.arguments.contains("--benchmark")
        do {
            renderer = try OceanRenderer(view: viewport, diagnostics: diagnostics, options: options)
            if OceanRunMode.offscreen {
                // No NSWindow, display link, drawable acquisition or activation.
                renderer?.isPaused = false
                automationTimer = Timer.scheduledTimer(withTimeInterval: 1.0/Double(viewport.preferredFramesPerSecond), repeats: true) { [weak self] _ in
                    guard let self else { return }
                    self.renderer?.draw(in:self.viewport)
                }
                automationTimer?.tolerance = 0
            } else {
                if OceanRunMode.wallpaper { installWallpaperControls() }
                updatePlayback()
            }
            if diagnostics {
                Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.renderer?.printDiagnostics() }
            }
        } catch { showError(error.localizedDescription) }
        if OceanRunMode.offscreen { return }
        let options = self.options
        let weather=WeatherProvider();weatherProvider=weather
        weather.onChange={ [weak self] value in self?.renderer?.setLocalWeather(value) }
        weather.onStatus={ [weak self] text in if self?.followsWeather == true { self?.weatherStatus?.title=text } }
        if renderer?.dayNightEnabled == true || options["weather"] != "0" {
            let provider=ObserverLocationProvider()
            locationProvider=provider
            provider.onChange={ [weak self] location,zone in
                self?.renderer?.setObserverLocation(location,timeZone:zone)
                if options["weather"] != "0" { self?.weatherProvider?.setLocation(location) }
            }
            provider.onStatus={ [weak self] status in self?.daylightStatus?.title=status }
            renderer?.onLocationMaintenance={ [weak provider,weak weather] in provider?.refresh();weather?.refresh() }
            renderer?.onSolarDayChanged={ [weak self] day in
                let formatter=DateFormatter();formatter.timeStyle = .short;formatter.timeZone=TimeZone(identifier:day.timeZoneID)
                func time(_ stamp: Double?) -> String { stamp.map { formatter.string(from:Date(timeIntervalSince1970:$0)) } ?? "—" }
                if day.daylight=="polarDay" { self?.solarTimesItem?.title="Midnight sun — no sunset today" }
                else if day.daylight=="polarNight" { self?.solarTimesItem?.title="Polar night — no sunrise today" }
                else { self?.solarTimesItem?.title="Sunrise \(time(day.sunrise)) · Sunset \(time(day.sunset))" }
            }
            renderer?.setObserverLocation(provider.location,timeZone:provider.timeZone)
            if options["weather"] != "0" { weather.setLocation(provider.location) }
            provider.refresh()
        } else { daylightStatus?.title="Fixed lighting preview" }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification,NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidSleepNotification,NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification,NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(self,selector:#selector(powerOrSessionChanged(_:)),name:name,object:nil)
        }
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked","com.apple.screenIsUnlocked","com.apple.screensaver.didstart","com.apple.screensaver.didstop"] {
            distributed.addObserver(self,selector:#selector(lockOrScreenSaverChanged(_:)),name:Notification.Name(name),object:nil)
        }
    }

    private func makeView(frame: NSRect, device: MTLDevice) -> MTKView {
        let view = MTKView(frame: frame, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.autoResizeDrawable = false
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 30
        if let layer = view.layer as? CAMetalLayer {
            layer.maximumDrawableCount = 2
            layer.displaySyncEnabled = true
            layer.isOpaque = true
        }
        return view
    }

    // MARK: Wallpaper surfaces

    private func buildSurfaces() {
        guard let device else { return }
        for surface in surfaces { surface.window.orderOut(nil); surface.window.close() }
        surfaces.removeAll()
        let screens = allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        for screen in screens {
            let window = WallpaperWindow(screen: screen)
            let view = makeView(frame: NSRect(origin: .zero, size: screen.frame.size), device: device)
            window.contentView = view
            window.delegate = self
            window.orderFrontRegardless()
            surfaces.append(WallpaperSurface(screen: screen, window: window, view: view))
        }
        sizeSecondaryDrawables()
        renderer?.layoutView = surfaces.first?.view
    }

    private func sizeSecondaryDrawables() {
        for surface in surfaces.dropFirst() {
            let layout = ViewportLayout(pointWidth: Double(surface.screen.frame.width), pointHeight: Double(surface.screen.frame.height),
                                        backingScale: Double(surface.screen.backingScaleFactor), pixelBudget: decision.pixelBudget)
            surface.view.drawableSize = CGSize(width: layout.width, height: layout.height)
        }
    }

    @objc private func screensChanged() {
        guard OceanRunMode.wallpaper else { return }
        buildSurfaces()
        if let first = surfaces.first?.view { first.delegate = renderer }
        refreshCoverage()
    }

    private func installWallpaperControls() {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "water.waves", accessibilityDescription: "Ocean wallpaper")
            if button.image == nil { button.title = "≋" }
        }
        let menu = NSMenu()
        let status = NSMenuItem(title: "Ocean wallpaper", action: nil, keyEquivalent: "")
        menu.addItem(status); performanceStatus = status
        let pause = NSMenuItem(title: "Pause Wallpaper", action: #selector(togglePause), keyEquivalent: "p")
        pause.target = self; menu.addItem(pause); pauseItem = pause
        menu.addItem(.separator())
        for entry in environmentMenuItems() { menu.addItem(entry) }
        let performance = NSMenuItem(title: "Performance", action: nil, keyEquivalent: "")
        let performanceMenu = NSMenu(title: "Performance")
        performanceMenu.addItem(NSMenuItem(title: "Frame Rate", action: nil, keyEquivalent: ""))
        for (title, fps) in [("Adaptive (30, saves power)", 0), ("60 FPS", 60), ("30 FPS", 30), ("20 FPS", 20), ("15 FPS", 15)] {
            let entry = NSMenuItem(title: "   " + title, action: #selector(chooseRate(_:)), keyEquivalent: "")
            entry.target = self; entry.tag = fps; performanceMenu.addItem(entry); rateItems.append(entry)
        }
        performanceMenu.addItem(.separator())
        performanceMenu.addItem(NSMenuItem(title: "Render Resolution", action: nil, keyEquivalent: ""))
        for (title, budget) in [("Efficient · 0.7 MP", 0.7e6), ("Balanced · 1.0 MP", PerformancePolicy.balancedBudget), ("Sharp · 2.0 MP", 2.0e6), ("Ultra · 3.7 MP", 3.7e6)] {
            let entry = NSMenuItem(title: "   " + title, action: #selector(chooseQuality(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = budget; performanceMenu.addItem(entry); qualityItems.append(entry)
        }
        performance.submenu = performanceMenu; menu.addItem(performance)
        let displays = NSMenuItem(title: "Displays", action: nil, keyEquivalent: "")
        let displaysMenu = NSMenu(title: "Displays")
        for (title, all) in [("All Displays", true), ("Main Display Only", false)] {
            let entry = NSMenuItem(title: title, action: #selector(chooseDisplays(_:)), keyEquivalent: "")
            entry.target = self; entry.tag = all ? 1 : 0; displaysMenu.addItem(entry); displayItems.append(entry)
        }
        displays.submenu = displaysMenu; menu.addItem(displays)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self; menu.addItem(login); loginItem = login
        menu.addItem(withTitle: "Quit Ocean", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        refreshMenuState()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(performanceInputsChanged), name: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(performanceInputsChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspace.addObserver(self, selector: #selector(performanceInputsChanged), name: name, object: nil)
        }
        refreshCoverage()
    }

    private func refreshMenuState() {
        for item in rateItems { item.state = item.tag == requestedFPS ? .on : .off }
        for item in qualityItems { item.state = abs((item.representedObject as? Double ?? 0)-requestedBudget) < 1 ? .on : .off }
        for item in displayItems { item.state = (item.tag == 1) == allDisplays ? .on : .off }
        pauseItem?.title = suspension.isSuspended(.userPaused) ? "Resume Wallpaper" : "Pause Wallpaper"
        loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func chooseRate(_ item: NSMenuItem) { defaults.set(item.tag, forKey: "OceanFramesPerSecond"); refreshMenuState(); refreshCoverage() }
    @objc private func chooseQuality(_ item: NSMenuItem) {
        defaults.set(item.representedObject as? Double ?? PerformancePolicy.balancedBudget, forKey: "OceanPixelBudget"); refreshMenuState(); refreshCoverage()
    }
    @objc private func chooseDisplays(_ item: NSMenuItem) {
        defaults.set(item.tag == 1, forKey: "OceanAllDisplays"); refreshMenuState(); screensChanged()
    }
    @objc private func togglePause() {
        suspension.set(.userPaused, active: !suspension.isSuspended(.userPaused)); refreshMenuState(); updatePlayback()
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert(); alert.messageText = "Open at Login is unavailable"
            alert.informativeText = "Move Ocean.app to /Applications and try again.\n\(error.localizedDescription)"; alert.runModal()
        }
        refreshMenuState()
    }
    @objc private func performanceInputsChanged() { refreshCoverage() }

    // Samples on-screen window bounds (no Screen Recording permission needed)
    // to estimate how much of each desktop is uncovered.
    private func refreshCoverage() {
        guard OceanRunMode.wallpaper else { return }
        let now = CACurrentMediaTime()
        if now-lastPowerCheck > 10 {
            lastPowerCheck = now
            if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
               let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? {
                onBattery = source == "Battery Power"
            }
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var covers: [CGRect] = []
        let me = ProcessInfo.processInfo.processIdentifier
        if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for info in list {
                guard (info[kCGWindowLayer as String] as? Int) == 0,
                      (info[kCGWindowOwnerPID as String] as? Int32) != me,
                      (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.5,
                      let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
                covers.append(rect)
            }
        }
        visibleFraction.removeAll()
        for surface in surfaces {
            let f = surface.screen.frame
            let cg = CGRect(x: f.minX, y: primaryHeight-f.maxY, width: f.width, height: f.height)
            let id = (surface.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            visibleFraction[id] = DesktopCoverage.visibleFraction(of: cg, covers: covers)
        }
        var input = PerformanceInputs()
        input.requestedFPS = requestedFPS
        input.displayMaxFPS = surfaces.map { $0.screen.maximumFramesPerSecond }.max() ?? 60
        input.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        input.onBattery = onBattery
        input.thermal = PerformanceInputs.Thermal(rawValue: ProcessInfo.processInfo.thermalState.rawValue) ?? .nominal
        input.visibleFraction = visibleFraction.values.max() ?? 1
        input.requestedPixelBudget = requestedBudget
        let next = PerformancePolicy.decide(input)
        let budgetChanged = next.pixelBudget != decision.pixelBudget
        decision = next
        if budgetChanged { renderer?.pixelBudget = next.pixelBudget; sizeSecondaryDrawables() }
        updatePlayback()
        // Poll faster while throttled so a revealed desktop resumes promptly.
        let interval = next.framesPerSecond < 15 ? 0.25 : 0.75
        if coverageTimer?.timeInterval != interval {
            coverageTimer?.invalidate()
            coverageTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refreshCoverage() }
            coverageTimer?.tolerance = interval*0.3
        }
    }

    // MARK: Environment menus (shared by preview window and wallpaper)

    private func environmentMenuItems() -> [NSMenuItem] {
        let daylightItem=NSMenuItem(title:"Daylight",action:nil,keyEquivalent:"")
        let daylightMenu=NSMenu(title:"Daylight")
        let status=NSMenuItem(title:"Daylight follows your approximate IP location",action:nil,keyEquivalent:"")
        daylightMenu.addItem(status);daylightStatus=status
        let times=NSMenuItem(title:"Sunrise — · Sunset —",action:nil,keyEquivalent:"")
        daylightMenu.addItem(times);solarTimesItem=times
        daylightMenu.addItem(.separator())
        let refresh=NSMenuItem(title:"Refresh Approximate Location",action:#selector(refreshLocation),keyEquivalent:"")
        refresh.target=self;daylightMenu.addItem(refresh)
        daylightItem.submenu=daylightMenu
        let weatherItem=NSMenuItem(title:"Weather",action:nil,keyEquivalent:"");let weatherMenu=NSMenu(title:"Weather")
        let weatherText=NSMenuItem(title:"Waiting for approximate location…",action:nil,keyEquivalent:"")
        weatherStatus=weatherText;weatherMenu.addItem(weatherText)
        for (title,action) in [("Follow Local Weather",#selector(followWeather)),("Refresh Local Weather",#selector(refreshWeather))] {
            let item=NSMenuItem(title:title,action:action,keyEquivalent:"");item.target=self;weatherMenu.addItem(item)
        }
        weatherMenu.addItem(.separator())
        for (title,level) in [("Clear / Fair",0.0),("Light Drizzle",0.08),("Steady Rain",0.4),("Thunderstorm",0.75),("Hurricane",1.0)] {
            let item=NSMenuItem(title:title,action:#selector(weatherPreset(_:)),keyEquivalent:"")
            item.target=self;item.representedObject=level;weatherMenu.addItem(item)
        }
        let sliderItem=NSMenuItem();let controls=NSView(frame:NSRect(x:0,y:0,width:260,height:54))
        let label=NSTextField(labelWithString:"Storm strength · drizzle to hurricane")
        label.frame=NSRect(x:16,y:32,width:236,height:18);controls.addSubview(label)
        let slider=NSSlider(value:0,minValue:0,maxValue:1,target:self,action:#selector(stormStrength(_:)))
        slider.isContinuous=true;slider.frame=NSRect(x:16,y:6,width:228,height:24);controls.addSubview(slider);stormSlider=slider
        sliderItem.view=controls;weatherMenu.addItem(sliderItem)
        weatherItem.submenu=weatherMenu
        return [daylightItem,weatherItem]
    }

    @objc private func followWeather() { followsWeather=true;renderer?.followLocalWeather();weatherProvider?.refresh();weatherStatus?.title="Following local weather · Open-Meteo" }
    @objc private func refreshWeather() { weatherProvider?.refresh(force:true) }
    @objc private func weatherPreset(_ item:NSMenuItem) {
        guard let value=item.representedObject as? Double else { return }
        followsWeather=false;stormSlider?.doubleValue=value;renderer?.previewStorm(value);weatherStatus?.title="Preview · \(item.title) · transitions gradually"
    }
    @objc private func stormStrength(_ slider:NSSlider) {
        followsWeather=false;renderer?.previewStorm(slider.doubleValue);weatherStatus?.title="Storm preview · \(Int(slider.doubleValue*100))% · transitions gradually"
    }
    @objc private func refreshLocation() { locationProvider?.refresh(force:true) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { OceanRunMode.preview }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let window else { return false }
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        return true
    }
    func windowDidChangeOcclusionState(_ notification: Notification) { updatePlayback() }
    func windowDidMiniaturize(_ notification: Notification) { updatePlayback() }
    func windowDidDeminiaturize(_ notification: Notification) { updatePlayback() }
    @objc private func powerOrSessionChanged(_ notification: Notification) {
        switch notification.name {
        case NSWorkspace.willSleepNotification: suspension.set(.systemSleep,active:true)
        case NSWorkspace.didWakeNotification: suspension.set(.systemSleep,active:false)
        case NSWorkspace.screensDidSleepNotification: suspension.set(.displaySleep,active:true)
        case NSWorkspace.screensDidWakeNotification: suspension.set(.displaySleep,active:false)
        case NSWorkspace.sessionDidResignActiveNotification: suspension.set(.inactiveSession,active:true)
        case NSWorkspace.sessionDidBecomeActiveNotification: suspension.set(.inactiveSession,active:false)
        default: return
        }
        if !suspension.isSuspended { locationProvider?.refresh();weatherProvider?.refresh() }
        updatePlayback()
    }
    @objc private func lockOrScreenSaverChanged(_ notification: Notification) {
        switch notification.name.rawValue {
        case "com.apple.screenIsLocked": suspension.set(.screenLocked,active:true)
        case "com.apple.screenIsUnlocked": suspension.set(.screenLocked,active:false)
        case "com.apple.screensaver.didstart": suspension.set(.screenSaver,active:true)
        case "com.apple.screensaver.didstop": suspension.set(.screenSaver,active:false)
        default: return
        }
        updatePlayback()
    }

    private func updatePlayback() {
        guard let renderer else { return }
        if OceanRunMode.wallpaper { updateWallpaperPlayback(renderer); return }
        guard let window else { return }
        let visible = !window.isMiniaturized && window.occlusionState.contains(.visible)
        let request = SurfaceDemandRequest(surfaceID:"preview",worldID:"preview-world",
            visibility:visible ? .visible : .occluded,framesPerSecond:viewport.preferredFramesPerSecond,
            requiredWaveBands:0x3f)
        let demand = SharedSurfaceDemand.plan([request],suspended:suspension.isSuspended)
        let paused = demand["preview-world"]?.requiresGPUWork != true
        renderer.isPaused = paused
        viewport.isPaused = paused
    }

    // One world, many displays: the first visible surface drives the frame
    // clock; all visible surfaces receive a composite of the same HDR image.
    private func updateWallpaperPlayback(_ renderer: OceanRenderer) {
        let fps = decision.framesPerSecond
        let requests = surfaces.map { surface -> SurfaceDemandRequest in
            let id = (surface.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            let osVisible = surface.window.occlusionState.contains(.visible)
            let uncovered = (visibleFraction[id] ?? 1) > 0
            return SurfaceDemandRequest(surfaceID: "display-\(id)", worldID: "ocean", visibility: osVisible && uncovered ? .visible : .occluded,
                                        framesPerSecond: max(1, fps), requiredWaveBands: 0x3f)
        }
        let demand = SharedSurfaceDemand.plan(requests, suspended: suspension.isSuspended || fps == 0)
        let active = demand["ocean"]?.surfaceIDs ?? []
        let visibleViews = zip(surfaces, requests).filter { active.contains($0.1.surfaceID) }.map { $0.0.view }
        renderer.presentationSurfaces = visibleViews
        renderer.layoutView = surfaces.first?.view
        let driver = visibleViews.first
        for surface in surfaces {
            let drives = surface.view === driver
            if drives {
                surface.view.delegate = renderer
                if surface.view.preferredFramesPerSecond != max(1, fps) { surface.view.preferredFramesPerSecond = max(1, fps) }
            } else if surface.view.delegate != nil { surface.view.delegate = nil }
            surface.view.isPaused = !drives
        }
        renderer.isPaused = driver == nil
        let state: String
        if suspension.isSuspended(.userPaused) { state = "Paused" }
        else if driver == nil { state = "Idle · desktop covered" }
        else { state = "Live · \(fps) FPS · \(decision.reason)" }
        if performanceStatus?.title != state { performanceStatus?.title = state }
    }

    private func showError(_ message: String) {
        fputs("Ocean failed: \(message)\n", stderr)
        if OceanRunMode.offscreen || CommandLine.arguments.contains("--diagnostics") || CommandLine.arguments.contains("--verify") || CommandLine.arguments.contains("--benchmark") { exit(1) }
        let alert = NSAlert()
        alert.messageText = "Unable to open Ocean"
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = OceanApp()
app.delegate = delegate
app.setActivationPolicy(OceanRunMode.offscreen ? .prohibited : OceanRunMode.wallpaper ? .accessory : .regular)
app.run()
