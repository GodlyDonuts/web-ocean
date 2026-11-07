import AppKit

enum OceanInstaller {
    // Copy completely before replacing anything. Only an existing Ocean bundle
    // can be replaced; keep it in the Trash so an interrupted update is recoverable.
    static func stageCopy(source:URL,destination:URL)throws {
        let fm=FileManager.default
        if fm.fileExists(atPath:destination.path) {
            let info=destination.appendingPathComponent("Contents/Info.plist")
            let data=try Data(contentsOf:info)
            let plist=try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any]
            guard plist?["CFBundleIdentifier"] as? String == "local.wallpaper.ocean" else {
                throw NSError(domain:"OceanInstall",code:1,userInfo:[NSLocalizedDescriptionKey:"Another app is named Ocean. Please rename it before installing."])
            }
        }
        try fm.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
        let staged=destination.deletingLastPathComponent().appendingPathComponent(".Ocean-install-"+UUID().uuidString)
        defer { try? fm.removeItem(at:staged) }
        try fm.copyItem(at:source,to:staged)
        guard fm.isExecutableFile(atPath:staged.appendingPathComponent("Contents/MacOS/Ocean").path) else {
            throw NSError(domain:"OceanInstall",code:2,userInfo:[NSLocalizedDescriptionKey:"The download is incomplete. Download Ocean again from GitHub."])
        }
        var trashed:NSURL?
        if fm.fileExists(atPath:destination.path) { try fm.trashItem(at:destination,resultingItemURL:&trashed) }
        do { try fm.moveItem(at:staged,to:destination) }
        catch {
            if let trashed,!fm.fileExists(atPath:destination.path) { try? fm.moveItem(at:trashed as URL,to:destination) }
            throw error
        }
    }
    static func installAndRelaunch() {
        let source=Bundle.main.bundleURL
        let fm=FileManager.default
        let folder=fm.isWritableFile(atPath:"/Applications") ? URL(fileURLWithPath:"/Applications") : fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        let destination=folder.appendingPathComponent("Ocean.app")
        let exists=fm.fileExists(atPath:destination.path)
        let alert=NSAlert();alert.messageText=exists ? "Update Ocean in Applications?" : "Install Ocean in Applications?"
        alert.informativeText="Ocean will copy itself to Applications and open there. This keeps it available after you close the download."
        alert.addButton(withTitle:exists ? "Update & Open" : "Install & Open");alert.addButton(withTitle:"Cancel")
        NSApp.setActivationPolicy(.regular);NSApp.activate(ignoringOtherApps:true)
        guard alert.runModal() == .alertFirstButtonReturn else { NSApp.terminate(nil);return }
        let others=NSRunningApplication.runningApplications(withBundleIdentifier:"local.wallpaper.ocean").filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        for app in others { app.terminate() }
        func finish(_ attempt:Int) {
            guard others.allSatisfy(\.isTerminated) else {
                if attempt<20 { DispatchQueue.main.asyncAfter(deadline:.now()+0.25) { finish(attempt+1) };return }
                failure("Quit the other copy of Ocean, then open this download again.");return
            }
            DispatchQueue.global(qos:.userInitiated).async {
                do {
                    try stageCopy(source:source,destination:destination)
                    // Executing a downloaded copy can register its embedded
                    // extension. Unregister only this transient copy, before
                    // opening the installed app at its stable location.
                    let plugin=source.appendingPathComponent("Contents/PlugIns/OceanLiveWallpaper.appex")
                    if fm.fileExists(atPath:plugin.path) {
                        let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/pluginkit");p.arguments=["-r",plugin.path]
                        p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.nullDevice
                        try p.run();p.waitUntilExit()
                    }
                    DispatchQueue.main.async {
                        let configuration=NSWorkspace.OpenConfiguration();configuration.createsNewApplicationInstance=true
                        configuration.arguments=["--installed-copy"]
                        NSWorkspace.shared.openApplication(at:destination,configuration:configuration) { app,error in
                            DispatchQueue.main.async {
                                if app != nil { NSApp.terminate(nil) }
                                else { failure(error?.localizedDescription ?? "Open Ocean from Applications to finish setup.") }
                            }
                        }
                    }
                } catch { DispatchQueue.main.async { failure(error.localizedDescription) } }
            }
        }
        finish(0)
    }
    static func showManualInstallHelp() {
        let alert=NSAlert();alert.messageText="Finish installing Ocean in Finder"
        alert.informativeText="macOS is still opening a temporary copy of Ocean. Close this copy, drag Ocean from the disk image into Applications using Finder, then open it from Applications."
        alert.addButton(withTitle:"Show Applications");alert.addButton(withTitle:"Close")
        NSApp.setActivationPolicy(.regular);NSApp.activate(ignoringOtherApps:true)
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(URL(fileURLWithPath:"/Applications")) }
        NSApp.terminate(nil)
    }
    private static func failure(_ message:String) {
        let alert=NSAlert();alert.messageText="Ocean couldn’t finish installing"
        alert.informativeText=message;alert.addButton(withTitle:"OK");alert.runModal();NSApp.terminate(nil)
    }
}
