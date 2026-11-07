import AppKit
import ExtensionFoundation
import MetalKit
import IOSurface
import IOKit.ps
import OSLog

let oceanLog=Logger(subsystem:"local.wallpaper.ocean.live",category:"wallpaper")
func debugLog(_ message:String) { oceanLog.notice("\(message,privacy:.public)") }
enum OceanRunMode { static let offscreen=false }

@main final class OceanLiveWallpaper: NSObject, AppExtension {
    override required init() {
        super.init()
        let path="/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework/WallpaperExtensionKit"
        guard dlopen(path,RTLD_NOW) != nil,OceanInstallSnapshotEncoder() else {
            debugLog("Wallpaper runtime ABI unavailable");return
        }
        debugLog("Ocean wallpaper extension ready")
    }
    var configuration: some AppExtensionConfiguration { OceanWallpaperConfiguration() }
}

final class OceanWallpaperWorld:NSObject {
    static var shared:OceanWallpaperWorld?
    var surfaces:[String:OceanRemoteSurface]=[:]
    private var renderer:OceanRenderer?
    private var timer:Timer?
    private var lastFrameTime:Double?
    private var frameIntervals:[Double]=[]
    private var nextPolicy = -Double.infinity
    private var nextLog = -Double.infinity
    private var fps=30
    private var pixelBudget=PerformancePolicy.balancedBudget
    private var snapshotPending=false
    private var lastEnvironment:ScreenSaverEnvironment.Saved?
    private var pendingEnvironment:ScreenSaverEnvironment.Saved?
    private var locked=false
    private var systemSaver=false
    private var lastActivityLog=""
    private var lastAwake:[String:Bool]=[:]
    override init() {
        super.init()
        for name in ["com.apple.screenIsLocked","com.apple.screenIsUnlocked","com.apple.screensaver.didstart","com.apple.screensaver.didstop"] {
            DistributedNotificationCenter.default().addObserver(self,selector:#selector(activityChanged(_:)),name:Notification.Name(name),object:nil)
        }
    }
    @objc private func activityChanged(_ event:Notification) {
        switch event.name.rawValue {
        case "com.apple.screenIsLocked":locked=true
        case "com.apple.screenIsUnlocked":locked=false
        case "com.apple.screensaver.didstart":systemSaver=true
        case "com.apple.screensaver.didstop":systemSaver=false
        default:return
        }
        nextPolicy = -Double.infinity
        begin(interval:1.0/30)
    }
    deinit { DistributedNotificationCenter.default().removeObserver(self) }
    static func releaseIfUnused() {
        if shared?.surfaces.isEmpty==true { shared?.timer?.invalidate();shared=nil }
    }
    func begin(interval:Double=1.0/30) {
        guard timer?.timeInterval != interval else { return }
        timer?.invalidate()
        let timer=Timer(timeInterval:interval,repeats:true) { [weak self] _ in self?.draw() }
        RunLoop.main.add(timer,forMode:.common);self.timer=timer
    }
    private func draw() {
        let now=CACurrentMediaTime()
        if now>=nextPolicy {
            nextPolicy=now+1
            pendingEnvironment=ScreenSaverEnvironment.readLive()
            if let session=CGSessionCopyCurrentDictionary() as? [String:Any] { locked=(session["CGSSessionScreenIsLocked"] as? Bool)==true }
            var input=PerformanceInputs()
            input.lowPowerMode=ProcessInfo.processInfo.isLowPowerModeEnabled
            input.thermal=PerformanceInputs.Thermal(rawValue:ProcessInfo.processInfo.thermalState.rawValue) ?? .nominal
            if let info=IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),let source=IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? { input.onBattery=source=="Battery Power" }
            let control=LiveWallpaperControl.read()
            let fullScreen=locked || systemSaver || surfaces.values.contains { $0.request.mode=="locked" }
            if let control,!fullScreen {
                input.requestedFPS=control.framesPerSecond;input.requestedPixelBudget=control.pixelBudget
                input.visibleFraction=control.framesPerSecond==0 ? 0 : 1
            }
            let decision=PerformancePolicy.decide(input)
            if fps != decision.framesPerSecond { lastFrameTime=nil;frameIntervals=[] }
            fps=decision.framesPerSecond;pixelBudget=decision.pixelBudget
            renderer?.pixelBudget=decision.pixelBudget
            begin(interval:fps==0 ? 0.5 : 1.0/Double(fps))
        }
        for (id,surface) in surfaces {
            let awake=surface.displayAwake
            if lastAwake[id]==false && awake { surface.recover(reason:"display-awake") }
            lastAwake[id]=awake
        }
        let active=surfaces.values.filter { surface in
            OceanPresentation.shouldRender(displayAwake:surface.displayAwake,hostSuspended:surface.request.suspended,sessionLocked:locked,presentationMode:surface.request.mode)
        }
        let activity="locked=\(locked) active=\(active.count)/\(surfaces.count) fps=\(fps)"
        if activity != lastActivityLog { lastActivityLog=activity;debugLog("Ocean activity: \(activity)") }
        guard let first=active.first else { begin(interval:0.5);return }
        guard renderer==nil || fps>0 else { return }
        do {
            if renderer==nil {
                renderer=try OceanRenderer(view:first.view,diagnostics:false,options:[:])
                renderer?.usesLayerDrawables=true
                debugLog("Ocean Metal renderer initialized")
            }
            guard let renderer else { return }
            renderer.pixelBudget=pixelBudget
            if let saved=pendingEnvironment,saved != lastEnvironment {
                lastEnvironment=saved
                renderer.setDaylightTime(DaylightTime(value:saved.daylightTime) ?? DaylightTime())
                renderer.setObserverLocation(saved.location,timeZone:saved.timeZoneID.flatMap(TimeZone.init(identifier:)))
                if let date=saved.weatherMeasuredAt,Date().timeIntervalSince(date)>=0,Date().timeIntervalSince(date)<86400,let weather=saved.weather { renderer.setLocalWeather(weather) }
                debugLog("Loaded Ocean environment; daylight=\(saved.daylightTime)")
            }
            renderer.presentationSurfaces=active.map(\.view);renderer.layoutView=first.view;renderer.isPaused=false
            let previous=renderer.submittedFrames
            renderer.draw(in:first.view)
            first.view.releaseDrawables()
            CATransaction.flush()
            if renderer.submittedFrames>previous {
                if let lastFrameTime,renderer.submittedFrames>3,frameIntervals.count<256 { frameIntervals.append((now-lastFrameTime)*1000) }
                lastFrameTime=now
            }
            if now>=nextLog {
                nextLog=now+5
                if frameIntervals.count>=12 {
                    let samples=frameIntervals.sorted()
                    debugLog("Ocean pacing ms median=\(samples[samples.count/2]) p95=\(samples[min(samples.count-1,Int(Double(samples.count)*0.95))]) max=\(samples.last!)")
                    frameIntervals=[]
                }
                debugLog("Ocean live submitted=\(renderer.submittedFrames) completed=\(renderer.completedFrames) presented=\(renderer.presentedDrawables) errors=\(renderer.errors) locked=\(locked) idle=\(active.contains { $0.request.idle }) fps=\(fps) surfaces=\(active.count)")
            }
        } catch { debugLog("Ocean render initialization failed: \(error.localizedDescription)") }
    }
    func recover(reason:String,delayed:Bool=true) {
        for surface in surfaces.values { surface.recover(reason:reason) }
        renderer?.presentationSurfaces=[];renderer?.layoutView=nil
        lastFrameTime=nil;frameIntervals=[];nextPolicy = -Double.infinity
        begin(interval:1.0/30)
        if delayed {
            DispatchQueue.main.asyncAfter(deadline:.now()+2) { [weak self] in self?.recover(reason:reason+"+2s",delayed:false) }
        }
    }
    func snapshot(_ reply:@escaping(Any?,Error?)->Void) {
        guard !snapshotPending,let renderer,let view=surfaces.values.first?.view else { reply(fallbackSnapshot(),nil);return }
        snapshotPending=true
        var completed=false
        renderer.snapshotRequested={ [weak self] data,width,height in
            guard !completed else { return };completed=true;self?.snapshotPending=false
            reply(makeSnapshot(data,width:width,height:height),nil)
        }
        func submit(_ attempt:Int) {
            guard !completed,renderer.snapshotRequested != nil else { return }
            let wasPaused=renderer.isPaused;renderer.isPaused=true
            renderer.draw(in:view);renderer.isPaused=wasPaused
            if renderer.snapshotRequested != nil,attempt<8 {
                DispatchQueue.main.asyncAfter(deadline:.now()+0.025) { submit(attempt+1) }
            } else if renderer.snapshotRequested != nil {
                renderer.snapshotRequested=nil;completed=true;self.snapshotPending=false;reply(fallbackSnapshot(),nil)
            }
        }
        submit(0)
    }

}

func makeSnapshot(_ bgra:Data,width:Int,height:Int) -> AnyObject? {
    guard let surface=IOSurface(properties:[.width:width,.height:height,.bytesPerElement:4,.bytesPerRow:((width*4+255)/256)*256,.pixelFormat:0x42475241]) else { return nil }
    surface.lock(options:[],seed:nil)
    bgra.withUnsafeBytes { raw in
        guard let base=raw.baseAddress else { return }
        for row in 0..<height { memcpy(surface.baseAddress.advanced(by:row*surface.bytesPerRow),base.advanced(by:row*width*4),width*4) }
    }
    surface.unlock(options:[],seed:nil)
    return OceanWrapSnapshot(surface) as AnyObject?
}
func fallbackSnapshot() -> AnyObject? {
    guard let url=Bundle.main.url(forResource:"OceanFallback",withExtension:"png"),let image=NSImage(contentsOf:url),
          let bitmap=NSBitmapImageRep(data:image.tiffRepresentation ?? Data()) else { return nil }
    let width=bitmap.pixelsWide,height=bitmap.pixelsHigh
    var pixels=Data(count:width*height*4)
    pixels.withUnsafeMutableBytes { raw in
        let bytes=raw.bindMemory(to:UInt8.self)
        for y in 0..<height { for x in 0..<width {
            let c=(bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB)) ?? .black
            let i=(y*width+x)*4
            bytes[i]=UInt8(max(0,min(255,c.blueComponent*255)));bytes[i+1]=UInt8(max(0,min(255,c.greenComponent*255)));bytes[i+2]=UInt8(max(0,min(255,c.redComponent*255)));bytes[i+3]=255
        } }
    }
    return makeSnapshot(pixels,width:width,height:height)
}

final class OceanWallpaperHandler:NSObject,WallpaperExtensionXPCProtocol {
    func acquire(withId id:Any?,request:Any?,reply:@escaping(Any?,Error?)->Void) {
        guard let id=requestID(id),let request=OceanRequest(request) else { reply(nil,NSError(domain:"OceanWallpaper",code:1));return }
        DispatchQueue.main.async {
            let world=OceanWallpaperWorld.shared ?? OceanWallpaperWorld();OceanWallpaperWorld.shared=world
            guard let surface=OceanRemoteSurface(request),let boxed=OceanWrapContext(OceanRemoteContextID(surface.context)) else { reply(nil,NSError(domain:"OceanWallpaper",code:2));return }
            world.surfaces[id]=surface
            debugLog("Acquire Ocean surface; mode=\(request.mode) suspended=\(request.suspended) size=\(request.size)")
            reply(boxed,nil);world.begin()
        }
    }
    func update(withId id:Any?,request:Any?,reply:@escaping(Error?)->Void) {
        let key=requestID(id)
        let state=request.flatMap { field($0,"activityState") }.map { String(describing:$0).lowercased() }
        let mode=request.flatMap { field($0,"presentationMode") }.map { String(describing:$0).lowercased() }
        let destination=OceanRequest(request)
        DispatchQueue.main.async {
            if let key,let world=OceanWallpaperWorld.shared,let surface=world.surfaces[key] {
                let old=surface.request
                if let destination { surface.request.size=destination.size;surface.request.scale=destination.scale;surface.request.display=destination.display }
                if let state { surface.request.suspended=state.contains("suspend") }
                if let mode { surface.request.mode=mode;surface.request.idle=mode.contains("idle") || mode.contains("saver") }
                debugLog("Update Ocean surface: mode=\(surface.request.mode) state=\(state ?? "unchanged") awake=\(surface.displayAwake)")
                let geometryChanged=old.size != surface.request.size || old.scale != surface.request.scale
                if geometryChanged || OceanPresentation.needsRecovery(oldMode:old.mode,newMode:surface.request.mode,wasSuspended:old.suspended,isSuspended:surface.request.suspended) {
                    world.recover(reason:geometryChanged ? "geometry" : "host-transition")
                }
                world.begin()
            }
            reply(nil)
        }
    }
    func invalidate(withId id:Any?,reply:@escaping(Error?)->Void) {
        let key=requestID(id)
        DispatchQueue.main.async { if let key { OceanWallpaperWorld.shared?.surfaces.removeValue(forKey:key) };OceanWallpaperWorld.releaseIfUnused();reply(nil) }
    }
    func snapshot(withId id:Any?,reply:@escaping(Any?,Error?)->Void) {
        DispatchQueue.main.async { if let world=OceanWallpaperWorld.shared { world.snapshot(reply) } else { reply(fallbackSnapshot(),nil) } }
    }
    func handleDebugRequest(for request:Any?,reply:@escaping(Any?,Error?)->Void) { reply(nil,nil) }
    func handleNotification(withNamed name:Any?,reply:@escaping(Error?)->Void) {
        let message=String(describing:name ?? "")
        debugLog("Ocean host notification: \(message)")
        if message.contains("hostDidWake") {
            DispatchQueue.main.async { OceanWallpaperWorld.shared?.recover(reason:"hostDidWake") }
        }
        reply(nil)
    }
}
