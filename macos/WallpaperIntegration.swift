import AppKit

// The live desktop window cannot appear in the loginwindow process. Publish a
// rare, complete still via the supported desktop-image API for the lock screen.
final class WallpaperIntegration {
    private var writing=false
    let screenSaverSetup=AutomaticScreenSaverSetup()
    private var slot=0
    private let queue=DispatchQueue(label:"Ocean.wallpaper-still",qos:.utility)
    var status="System wallpaper has not been updated"
    private var lastStill: (URL,[NSScreen])?
    init() {
        screenSaverSetup.onSelectionReady={ [weak self] in
            guard let self,let (url,screens)=self.lastStill else { return }
            // A WallpaperAgent reload can race the asynchronous public desktop
            // setter. Reapply after selection has settled, without another frame.
            for screen in screens {
                do { try NSWorkspace.shared.setDesktopImageURL(url,for:screen,options:[.imageScaling:NSImageScaling.scaleProportionallyUpOrDown.rawValue,.allowClipping:true]) }
                catch { self.status="System wallpaper: \(error.localizedDescription)" }
            }
        }
        screenSaverSetup.onRestored={ [weak self] in self?.restoreDesktop() }
    }

    func publish(_ bgra: Data, width: Int, height: Int, screens: [NSScreen]) {
        guard !writing,width>0,height>0,bgra.count==width*height*4 else { return }
        writing=true;slot=1-slot
        let url=CelestialCycle.supportDirectory.appendingPathComponent("ocean-lock-\(slot).png")
        queue.async {
            do {
                let rgba=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:width*4,bitsPerPixel:32)!
                let destination=rgba.bitmapData!
                bgra.withUnsafeBytes { raw in
                    let source=raw.bindMemory(to:UInt8.self)
                    for i in stride(from:0,to:bgra.count,by:4) {
                        destination[i]=source[i+2];destination[i+1]=source[i+1];destination[i+2]=source[i];destination[i+3]=255
                    }
                }
                guard let png=rgba.representation(using:.png,properties:[:]) else { throw OceanFailure(message:"Cannot encode system wallpaper") }
                try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
                try png.write(to:url,options:.atomic)
                DispatchQueue.main.async {
                    do {
                        var original=UserDefaults.standard.dictionary(forKey:"OceanPreviousDesktopImages") as? [String:String] ?? [:]
                        for screen in screens {
                            let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "0"
                            if original[id]==nil,let previous=NSWorkspace.shared.desktopImageURL(for:screen),!previous.lastPathComponent.hasPrefix("ocean-lock-") { original[id]=previous.absoluteString }
                            // Save restoration information before changing OS preferences.
                            UserDefaults.standard.set(original,forKey:"OceanPreviousDesktopImages")
                            try NSWorkspace.shared.setDesktopImageURL(url,for:screen,options:[.imageScaling:NSImageScaling.scaleProportionallyUpOrDown.rawValue,.allowClipping:true])
                        }
                        ScreenSaverEnvironment.publishFromApp()
                        self.lastStill=(url,screens)
                        self.status="System wallpaper updated"
                        self.screenSaverSetup.enableIfNeeded()
                    } catch { self.status="System wallpaper: \(error.localizedDescription)" }
                    self.writing=false
                }
            } catch {
                DispatchQueue.main.async { self.status="System wallpaper: \(error.localizedDescription)";self.writing=false }
            }
        }
    }

    func restore() { screenSaverSetup.restore() }
    private func restoreDesktop() {
        let original=UserDefaults.standard.dictionary(forKey:"OceanPreviousDesktopImages") as? [String:String] ?? [:]
        for screen in NSScreen.screens {
            let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "0"
            if let value=original[id],let url=URL(string:value) { try? NSWorkspace.shared.setDesktopImageURL(url,for:screen,options:[:]) }
        }
    }
}

