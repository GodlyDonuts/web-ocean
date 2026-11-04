import AppKit
import MetalKit

enum OceanRunMode {
    static let offscreen = (CommandLine.arguments.contains("--verify") || CommandLine.arguments.contains("--benchmark"))
        && !CommandLine.arguments.contains("--windowed-test")
}

final class OceanApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var viewport: MTKView!
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        var options: [String: String] = [:]
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--query=") }),
           let items = URLComponents(string: "?" + argument.dropFirst(8))?.queryItems {
            for item in items { options[item.name] = item.value }
        }
        if !OceanRunMode.offscreen {
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
            let daylightItem=NSMenuItem()
            let daylightMenu=NSMenu(title:"Daylight")
            let status=NSMenuItem(title:"Daylight follows your approximate IP location",action:nil,keyEquivalent:"")
            daylightMenu.addItem(status);daylightStatus=status
            let times=NSMenuItem(title:"Sunrise — · Sunset —",action:nil,keyEquivalent:"")
            daylightMenu.addItem(times);solarTimesItem=times
            daylightMenu.addItem(.separator())
            daylightMenu.addItem(withTitle:"Refresh Approximate Location",action:#selector(refreshLocation),keyEquivalent:"")
            daylightItem.submenu=daylightMenu;menu.addItem(daylightItem)
            let weatherItem=NSMenuItem();let weatherMenu=NSMenu(title:"Weather")
            let weatherText=NSMenuItem(title:"Waiting for approximate location…",action:nil,keyEquivalent:"")
            weatherStatus=weatherText;weatherMenu.addItem(weatherText)
            weatherMenu.addItem(withTitle:"Follow Local Weather",action:#selector(followWeather),keyEquivalent:"")
            weatherMenu.addItem(withTitle:"Refresh Local Weather",action:#selector(refreshWeather),keyEquivalent:"")
            weatherMenu.addItem(.separator())
            for (title,level) in [("Clear / Fair",0.0),("Light Drizzle",0.08),("Steady Rain",0.4),("Thunderstorm",0.75),("Hurricane",1.0)] {
                let item=NSMenuItem(title:title,action:#selector(weatherPreset(_:)),keyEquivalent:"")
                item.representedObject=level;weatherMenu.addItem(item)
            }
            let sliderItem=NSMenuItem();let controls=NSView(frame:NSRect(x:0,y:0,width:260,height:54))
            let label=NSTextField(labelWithString:"Storm strength · drizzle to hurricane")
            label.frame=NSRect(x:16,y:32,width:236,height:18);controls.addSubview(label)
            let slider=NSSlider(value:0,minValue:0,maxValue:1,target:self,action:#selector(stormStrength(_:)))
            slider.isContinuous=true;slider.frame=NSRect(x:16,y:6,width:228,height:24);controls.addSubview(slider);stormSlider=slider
            sliderItem.view=controls;weatherMenu.addItem(sliderItem)
            weatherItem.submenu=weatherMenu;menu.addItem(weatherItem)
            NSApp.mainMenu = menu
        }

        guard let device = MTLCreateSystemDefaultDevice() else { showError("This Mac does not support Metal."); return }
        func dimension(_ key: String, fallback: Double, minimum: Double) -> CGFloat {
            guard let number = Double(options[key] ?? ""), number.isFinite, number > 0 else { return CGFloat(fallback) }
            return CGFloat(max(minimum,min(8192,number)))
        }
        viewport = MTKView(frame: NSRect(x:0,y:0,width:dimension("width",fallback:1200,minimum:640),
                                      height:dimension("height",fallback:750,minimum:400)),device:device)
        viewport.colorPixelFormat = .bgra8Unorm
        viewport.framebufferOnly = !CommandLine.arguments.contains("--verify")
        viewport.autoResizeDrawable = false
        viewport.isPaused = true
        viewport.enableSetNeedsDisplay = false
        viewport.preferredFramesPerSecond = 30
        if !OceanRunMode.offscreen {
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
                updatePlayback()
            }
            if diagnostics {
                Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.renderer?.printDiagnostics() }
            }
        } catch { showError(error.localizedDescription) }
        if OceanRunMode.offscreen { return }
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
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

    private func updatePlayback() {
        guard let renderer, let window else { return }
        let visible = !window.isMiniaturized && window.occlusionState.contains(.visible)
        let request = SurfaceDemandRequest(surfaceID:"preview",worldID:"preview-world",
            visibility:visible ? .visible : .occluded,framesPerSecond:viewport.preferredFramesPerSecond,
            requiredWaveBands:0x3f)
        let demand = SharedSurfaceDemand.plan([request],suspended:suspension.isSuspended)
        let paused = demand["preview-world"]?.requiresGPUWork != true
        renderer.isPaused = paused
        viewport.isPaused = paused
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
app.setActivationPolicy(OceanRunMode.offscreen ? .prohibited : .regular)
app.run()
