import AppKit

// Explicit, brief interactive check. One click-through desktop-level window;
// never run by unit tests, CI or the product. No focus/keyboard/security changes.
@main struct RegionalCoverageProbe {
    static func main() {
        guard CommandLine.arguments.contains("--present") else {
            print("Use --present for a 14-second desktop coverage test: right 75%, full coverage, reveal. No windows otherwise.")
            return
        }
        if let session=CGSessionCopyCurrentDictionary() as? [String:Any],(session["CGSSessionScreenIsLocked"] as? Bool)==true {
            fputs("Unlock the Mac before the interactive coverage probe. No windows created.\n",stderr);exit(2)
        }
        let app=NSApplication.shared
        app.setActivationPolicy(.accessory)
        guard let screen=NSScreen.screens.first else { return }
        let frame=screen.frame
        let cover=NSWindow(contentRect:CGRect(x:frame.minX+frame.width*0.25,y:frame.minY,width:frame.width*0.75,height:frame.height),styleMask:.borderless,backing:.buffered,defer:false)
        cover.level = .normal
        cover.collectionBehavior=[.canJoinAllSpaces,.stationary,.ignoresCycle,.fullScreenNone]
        cover.ignoresMouseEvents=true;cover.hasShadow=false;cover.isOpaque=true
        cover.backgroundColor=NSColor(calibratedWhite:0.02,alpha:1)
        cover.isReleasedWhenClosed=false;cover.animationBehavior = .none
        cover.orderBack(nil);print("REGIONAL PROBE: right 75% covered")
        Timer.scheduledTimer(withTimeInterval:7,repeats:false) { _ in
            cover.setFrame(frame,display:true);print("REGIONAL PROBE: completely covered")
        }
        Timer.scheduledTimer(withTimeInterval:12,repeats:false) { _ in
            cover.orderOut(nil);cover.close();print("REGIONAL PROBE: revealed")
        }
        Timer.scheduledTimer(withTimeInterval:14,repeats:false) { _ in app.terminate(nil) }
        app.run()
    }
}
