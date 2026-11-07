import AppKit
import MetalKit
import ScreenSaver
import IOKit.ps

// The ScreenSaver host owns lifecycle/presentation; the exact same native
// renderer/shaders serve the wallpaper and saver. No wallpaper windows here.
enum OceanRunMode { static let offscreen=false }

// Full-screen hosts share a world in this process; settings thumbnails get an
// independent small-budget world so a preview cannot resize the active saver.
private final class SaverWorld {
    static var fullScreen: SaverWorld?
    let renderer: OceanRenderer
    var views: [MTKView]=[]
    private let preview: Bool
    private var nextPolicy = -Double.infinity
    private var cadence=FrameSubmissionCadence()
    private var policyDescription=""
    private(set) var framesPerSecond=30
    init(view: MTKView,preview: Bool) throws {
        self.preview=preview
        renderer=try OceanRenderer(view:view,diagnostics:false,options:[:])
        renderer.usesLayerDrawables=true
        refreshPolicy(at:CACurrentMediaTime())
        if let saved=ScreenSaverEnvironment.read() {
            renderer.setDaylightTime(DaylightTime(value:saved.daylightTime) ?? DaylightTime())
            renderer.setObserverLocation(saved.location,timeZone:saved.timeZoneID.flatMap(TimeZone.init(identifier:)))
            if let date=saved.weatherMeasuredAt,Date()>=date,Date().timeIntervalSince(date)<86400,
               let weather=saved.weather { renderer.setLocalWeather(weather) }
        } else {
            // First launch before the app has published its cached environment.
            let location=ObserverLocationProvider()
            renderer.setObserverLocation(location.location,timeZone:location.timeZone)
        }
    }
    func add(_ view: MTKView) { views.append(view);sync() }
    func remove(_ view: MTKView) {
        views.removeAll { $0 === view };sync()
        if views.isEmpty,SaverWorld.fullScreen === self { SaverWorld.fullScreen=nil }
    }
    private func sync() {
        renderer.presentationSurfaces=views;renderer.layoutView=views.first;renderer.isPaused=views.isEmpty
    }
    private func refreshPolicy(at time: Double) {
        guard time>=nextPolicy else { return };nextPolicy=time+5
        var input=PerformanceInputs()
        input.displayMaxFPS=views.first?.window?.screen?.maximumFramesPerSecond ?? 60
        input.requestedPixelBudget=preview ? 320*200 : PerformancePolicy.balancedBudget
        input.lowPowerMode=ProcessInfo.processInfo.isLowPowerModeEnabled
        input.thermal=PerformanceInputs.Thermal(rawValue:ProcessInfo.processInfo.thermalState.rawValue) ?? .nominal
        if let info=IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let source=IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? { input.onBattery=source=="Battery Power" }
        let decision=PerformancePolicy.decide(input)
        framesPerSecond=min(decision.framesPerSecond,preview ? 15 : 30)
        renderer.pixelBudget=decision.pixelBudget
        let description="\(framesPerSecond) FPS, \(decision.reason), \(Int(decision.pixelBudget)) pixels, preview=\(preview)"
        if description != policyDescription { policyDescription=description;NSLog("Ocean saver policy: %@",description) }
    }
    func draw(_ view: MTKView) {
        guard views.first === view else { return }
        let now=CACurrentMediaTime();refreshPolicy(at:now)
        guard cadence.shouldSubmit(at:now,framesPerSecond:framesPerSecond) else { return }
        renderer.draw(in:view)
        view.releaseDrawables()

    }
}

@objc(OceanScreenSaverView)
final class OceanScreenSaverView: ScreenSaverView {
    private var metalView: MTKView?
    private var world: SaverWorld?

    override init?(frame: NSRect,isPreview: Bool) {
        super.init(frame:frame,isPreview:isPreview)
        animationTimeInterval=1.0/30
        wantsLayer=true;layer?.backgroundColor=NSColor.black.cgColor
    }
    required init?(coder: NSCoder) { super.init(coder:coder) }
    override func startAnimation() {
        super.startAnimation()
        guard metalView==nil else { return }
        do {
            guard let device=SaverWorld.fullScreen?.renderer.device ?? MTLCreateSystemDefaultDevice() else { return }
            let view=MTKView(frame:bounds,device:device)
            view.autoresizingMask=[.width,.height]
            view.colorPixelFormat = .bgra8Unorm
            view.framebufferOnly=true;view.autoResizeDrawable=false
            view.isPaused=true;view.enableSetNeedsDisplay=false
            let shared: SaverWorld
            if !isPreview,let existing=SaverWorld.fullScreen { shared=existing }
            else { shared=try SaverWorld(view:view,preview:isPreview) }
            if !isPreview { SaverWorld.fullScreen=shared }
            shared.add(view)
            animationTimeInterval=1.0/Double(shared.framesPerSecond)
            addSubview(view);metalView=view;world=shared
        } catch { NSLog("Ocean screensaver: %@",error.localizedDescription) }
    }
    override func animateOneFrame() {
        guard let view=metalView else { return }
        world?.draw(view)
        if let world {
            let interval=1.0/Double(world.framesPerSecond)
            if abs(animationTimeInterval-interval)>0.00001 { animationTimeInterval=interval }
        }
    }
    override func stopAnimation() {
        super.stopAnimation()
        if let view=metalView { world?.remove(view);view.removeFromSuperview() }
        metalView=nil;world=nil
    }
}
