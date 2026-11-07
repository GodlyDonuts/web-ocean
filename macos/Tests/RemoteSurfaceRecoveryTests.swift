import AppKit
import MetalKit
func debugLog(_ message:String) { print(message) }
@main struct RemoteSurfaceRecoveryTests {
    static func main() {
        _=NSApplication.shared;NSApp.setActivationPolicy(.prohibited)
        struct Destination { var size=CGSize(width:320,height:200);var scaleFactor=CGFloat(2);var directDisplayID=CGMainDisplayID() }
        struct Request { var destination=Destination();var activityState="active";var presentationMode="locked" }
        guard CGDisplayIsOnline(CGMainDisplayID()) != 0,CGDisplayIsAsleep(CGMainDisplayID())==0 else {
            print("SKIP: remote presentation replacement requires an awake display; sleep policy is tested separately");return
        }
        let request=OceanRequest(Request())!
        guard let surface=OceanRemoteSurface(request) else { fatalError("Remote surface allocation failed") }
        let context=OceanRemoteContextID(surface.context)
        precondition(context>0)
        for _ in 0..<12 {
            let oldView=surface.view
            surface.recover(reason:"lifecycle-test")
            precondition(oldView.layer?.superlayer==nil,"Remove the stale layer from the hosted tree")
            precondition(oldView !== surface.view,"Recovery must replace the stale presentation object")
            precondition(surface.root.sublayers?.count==1,"Recovery must not accumulate layers")
            precondition(surface.view.bounds.size==request.size)
            precondition(OceanRemoteContextID(surface.context)==context,"Keep the context ID already hosted by macOS")
            precondition(surface.view.device != nil && surface.view.layer?.superlayer===surface.root)
        }
        precondition(surface.recoveries==12)
        precondition(NSApp.windows.isEmpty,"Recovery tests cannot open windows")
        print("PASS: twelve real remote Metal-view replacements, stable hosted context, bounded layer tree, geometry/device and zero windows")
    }
}
