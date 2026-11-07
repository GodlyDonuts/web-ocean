import AppKit
import ScreenSaver
import MetalKit

@main struct ScreenSaverLifecycleTests {
    static func main() throws {
        _=NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let url=URL(fileURLWithPath:CommandLine.arguments[1])
        guard let bundle=Bundle(url:url),bundle.load(),let kind=bundle.principalClass as? ScreenSaverView.Type,
              let view=kind.init(frame:NSRect(x:0,y:0,width:320,height:200),isPreview:true) else { fatalError("Cannot load Ocean saver") }
        for _ in 0..<2 {
            view.startAnimation()
            precondition(view.subviews.count==1,"One Metal view per lifecycle")
            precondition(view.subviews[0].bounds.size==view.bounds.size,"Preview fits host")
            view.animateOneFrame()
            view.stopAnimation()
            precondition(view.subviews.isEmpty,"Stopped saver releases its view")
        }
        // A second physical display must share the expensive world resources.
        let first=kind.init(frame:NSRect(x:0,y:0,width:640,height:400),isPreview:false)!
        let second=kind.init(frame:NSRect(x:0,y:0,width:640,height:400),isPreview:false)!
        first.startAnimation()
        let device=(first.subviews[0] as! MTKView).device!
        let allocation=device.currentAllocatedSize
        second.startAnimation()
        precondition(device.currentAllocatedSize < allocation+2_000_000,"Second display created another simulation")
        first.animateOneFrame();first.stopAnimation()
        second.animateOneFrame();second.stopAnimation()
        // Drain completion handoffs after stopping with a frame in flight.
        RunLoop.main.run(until:Date().addingTimeInterval(0.2))
        precondition(NSApp.windows.isEmpty,"Saver test must not open windows")
        print("PASS: native saver bundle/resource loading, start/stop/restart, shared multi-display allocation, in-flight teardown, zero windows")
    }
}
