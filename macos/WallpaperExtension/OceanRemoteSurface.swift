import AppKit
import MetalKit

// Request objects contain Swift value wrappers. Read named fields, with bounded
// recursion; reject missing destinations rather than guess a screen geometry.
func field(_ object:Any,_ name:String,depth:Int=0) -> Any? {
    guard depth<8 else { return nil }
    let mirror=Mirror(reflecting:object)
    for child in mirror.children where child.label==name { return child.value }
    for child in mirror.children { if let result=field(child.value,name,depth:depth+1) { return result } }
    return nil
}
func requestID(_ object:Any?) -> String? {
    guard let object else { return nil }
    let description=String(describing:Mirror(reflecting:object).children.first?.value ?? object)
    guard let range=description.range(of:"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",options:.regularExpression) else { return nil }
    return String(description[range])
}
struct OceanRequest {
    var size: CGSize
    var scale:CGFloat
    var display:UInt32
    var suspended:Bool
    var idle:Bool
    var mode:String
    init?(_ value:Any?) {
        guard let value,let destination=field(value,"destination"),let size=field(destination,"size") as? CGSize,
              size.width.isFinite,size.height.isFinite,size.width>0,size.height>0,size.width<20000,size.height<20000 else { return nil }
        self.size=size
        scale=(field(destination,"scaleFactor") as? CGFloat) ?? 1
        scale=max(1,min(4,scale))
        display=(field(destination,"directDisplayID") as? UInt32) ?? 0
        let state=field(value,"activityState").map { String(describing:$0).lowercased() } ?? "unknown"
        suspended=state.contains("suspend")
        let mode=field(value,"presentationMode").map { String(describing:$0).lowercased() } ?? "unknown"
        self.mode=mode
        idle=mode.contains("idle") || mode.contains("saver")
    }
}

final class OceanRemoteSurface {
    private(set) var view:MTKView
    let context:AnyObject
    let root:CALayer
    var request:OceanRequest
    var recoveries=0
    private var nextDisplayCheck = -Double.infinity
    private var cachedDisplayAwake=true
    private static func makeView(_ request:OceanRequest,device:MTLDevice) -> MTKView {
        let view=MTKView(frame:CGRect(origin:.zero,size:request.size),device:device)
        view.colorPixelFormat = .bgra8Unorm;view.framebufferOnly=true
        view.autoResizeDrawable=false;view.isPaused=true;view.enableSetNeedsDisplay=false
        if let layer=view.layer as? CAMetalLayer {
            layer.frame=CGRect(origin:.zero,size:request.size);layer.contentsScale=request.scale
            layer.presentsWithTransaction=false;layer.displaySyncEnabled=true
        }
        return view
    }
    init?(_ request:OceanRequest) {
        guard let device=MTLCreateSystemDefaultDevice() else { return nil }
        self.request=request;view=Self.makeView(request,device:device)
        root=CALayer();root.frame=CGRect(origin:.zero,size:request.size);root.isOpaque=true
        root.backgroundColor=NSColor(calibratedRed:0.012,green:0.03,blue:0.06,alpha:1).cgColor
        guard let layer=view.layer else { return nil };root.addSublayer(layer)
        guard let context=OceanCreateRemoteContext(root,request.scale,request.display),OceanRemoteContextID(context)>0 else { return nil }
        self.context=context as AnyObject;CATransaction.flush()
    }
    var displayAwake:Bool {
        let now=CACurrentMediaTime()
        if now>=nextDisplayCheck {
            nextDisplayCheck=now+0.5
            let id=request.display==0 ? CGMainDisplayID() : request.display
            cachedDisplayAwake=CGDisplayIsOnline(id) != 0 && CGDisplayIsAsleep(id)==0
        }
        return cachedDisplayAwake
    }
    func recover(reason:String) {
        nextDisplayCheck = -Double.infinity
        guard displayAwake,let device=view.device else { return }
        view.releaseDrawables();view.layer?.removeFromSuperlayer()
        view=Self.makeView(request,device:device)
        root.frame=CGRect(origin:.zero,size:request.size)
        if let layer=view.layer { root.addSublayer(layer) }
        CATransaction.flush();recoveries += 1
        debugLog("Recovered Ocean presentation: reason=\(reason) count=\(recoveries) mode=\(request.mode)")
    }
}

