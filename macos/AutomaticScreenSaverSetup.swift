import AppKit
import ScreenSaver

// macOS 14+ keeps saver selection in the WallpaperAgent store rather than the
// old moduleDict preference. The format is private: preserve unknown fields,
// back up before writing, verify after agent reload, and roll back on failure.
// Format reference: https://github.com/AerialScreensaver/PaperSaver
final class AutomaticScreenSaverSetup {
    static let identifier="local.wallpaper.ocean.screensaver"
    static let provider="com.apple.wallpaper.choice.screen-saver"
    private let queue=DispatchQueue(label:"Ocean.screensaver-setup",qos:.utility)
    private var attempted=false
    private var configuring=false
    var onStatus: ((String)->Void)?
    var onSelectionReady: (()->Void)?
    var onRestored: (()->Void)?
    var canReloadSaver: (()->Bool)?
    private let store=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    private let destination=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers/Ocean.saver")
    private let backup=CelestialCycle.supportDirectory.appendingPathComponent("before-ocean-screensaver.plist")

    static func canonicalModule(_ url: URL) -> URL { URL(fileURLWithPath:url.path,isDirectory:false).standardizedFileURL }
    static func selectedModule(_ section: [String:Any]) -> URL? {
        let slot=(section["Idle"] ?? section["Linked"]) as? [String:Any]
        guard let content=slot?["Content"] as? [String:Any],let choices=content["Choices"] as? [[String:Any]],
              let first=choices.first,first["Provider"] as? String==provider,let data=first["Configuration"] as? Data,
              let plist=try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any],
              let module=plist["module"] as? [String:Any],let path=module["relative"] as? String else { return nil }
        return URL(string:path)
    }
    static func sections(_ dictionary: [String:Any], transform: ([String:Any])->[String:Any]) -> [String:Any] {
        var result=dictionary
        for key in ["AllSpacesAndDisplays","SystemDefault"] {
            if let section=result[key] as? [String:Any] { result[key]=transform(section) }
        }
        if var displays=result["Displays"] as? [String:Any] {
            for (key,value) in displays { if let section=value as? [String:Any] { displays[key]=transform(section) } }
            result["Displays"]=displays
        }
        if var spaces=result["Spaces"] as? [String:Any] {
            for (key,value) in spaces {
                guard var entry=value as? [String:Any] else { continue }
                if let section=entry["Default"] as? [String:Any] { entry["Default"]=transform(section) }
                if var displays=entry["Displays"] as? [String:Any] {
                    for (id,value) in displays { if let section=value as? [String:Any] { displays[id]=transform(section) } }
                    entry["Displays"]=displays
                }
                spaces[key]=entry
            }
            result["Spaces"]=spaces
        }
        return result
    }
    static func selecting(_ module: URL, in dictionary: [String:Any]) throws -> [String:Any] {
        guard dictionary["AllSpacesAndDisplays"] is [String:Any],dictionary["SystemDefault"] is [String:Any] else {
            throw OceanFailure(message:"Unrecognized macOS wallpaper-store format")
        }
        let configuration=try PropertyListSerialization.data(fromPropertyList:["module":["relative":canonicalModule(module).absoluteString]],format:.binary,options:0)
        let options=try PropertyListSerialization.data(fromPropertyList:["values":[String:Any]()],format:.binary,options:0)
        let choice:[String:Any] = ["Provider":provider,"Configuration":configuration,"Files":[Any]()]
        let slot:[String:Any] = ["Content":["Choices":[choice],"Shuffle":"$null","EncodedOptionValues":options],"LastSet":Date(),"LastUse":Date()]
        return sections(dictionary) { original in
            var section=original
            if let linked=section.removeValue(forKey:"Linked"),section["Desktop"]==nil { section["Desktop"]=linked }
            section["Idle"]=slot
            section["Type"]=section["Desktop"]==nil ? "idle" : "individual"
            return section
        }
    }
    private func ready() {
        DispatchQueue.main.async {
            UserDefaults.standard.set(true,forKey:"OceanAutomaticScreenSaver")
            UserDefaults.standard.set(true,forKey:"OceanScreenSaverConfigured")
            self.reloadInstalledSaverIfNeeded()
            self.onStatus?("Ocean screen saver installed and selected");self.onSelectionReady?()
        }
    }
    // The legacy host caches loaded plug-in code. Refresh it once after an
    // actual module update, while unlocked, so users don't reinstall/reboot.
    private func reloadInstalledSaverIfNeeded() {
        guard UserDefaults.standard.bool(forKey:"OceanSaverNeedsReload"),canReloadSaver?() != false else { return }
        if let session=CGSessionCopyCurrentDictionary() as? [String:Any],(session["CGSSessionScreenIsLocked"] as? Bool)==true { return }
        UserDefaults.standard.set(false,forKey:"OceanSaverNeedsReload")
        let expected=URL(fileURLWithPath:"/System/Library/Frameworks/ScreenSaver.framework/PlugIns/legacyScreenSaver.appex").resolvingSymlinksInPath().path
        for app in NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.ScreenSaver.Engine.legacyScreenSaver")
            where app.bundleURL?.resolvingSymlinksInPath().path==expected {
            app.forceTerminate()
        }
    }
    func refreshRuntimeIfNeeded() {
        queue.async {
            guard UserDefaults.standard.bool(forKey:"OceanSaverNeedsReload"),
                  let data=try? Data(contentsOf:self.store),let dictionary=try? self.read(data),
                  let section=dictionary["AllSpacesAndDisplays"] as? [String:Any],
                  Self.selectedModule(section)?.path==self.destination.path else { return }
            DispatchQueue.main.async { self.reloadInstalledSaverIfNeeded() }
        }
    }
    private func status(_ text: String) { DispatchQueue.main.async { self.onStatus?(text) } }
    private func read(_ data: Data) throws -> [String:Any] {
        guard let result=try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any] else { throw OceanFailure(message:"Invalid wallpaper store") }
        return result
    }
    @discardableResult private func reloadAgent() -> Set<pid_t> {
        var ids=Set<pid_t>()
        DispatchQueue.main.sync {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.wallpaper.agent")
                where app.bundleURL?.path=="/System/Library/CoreServices/WallpaperAgent.app" {
                ids.insert(app.processIdentifier)
                if !app.terminate() { app.forceTerminate() }
            }
        }
        return ids
    }
    static func restoring(_ current: [String:Any], from original: [String:Any], module: URL) -> [String:Any] {
        let fallback=(original["AllSpacesAndDisplays"] as? [String:Any])?["Idle"]
            ?? (original["AllSpacesAndDisplays"] as? [String:Any])?["Linked"]
        func visit(_ now: [String:Any],_ old: [String:Any]) -> [String:Any] {
            var next=now
            if selectedModule(now)?.path==module.path {
                next["Idle"]=old["Idle"] ?? old["Linked"] ?? fallback
                next["Type"]=next["Desktop"]==nil ? "idle" : "individual"
                return next
            }
            for (key,value) in now {
                if let child=value as? [String:Any] { next[key]=visit(child,old[key] as? [String:Any] ?? [:]) }
            }
            return next
        }
        return visit(current,original)
    }
    func restore() {
        queue.async {
            defer { DispatchQueue.main.async { self.onRestored?() } }
            UserDefaults.standard.set(false,forKey:"OceanAutomaticScreenSaver")
            do {
                if #unavailable(macOS 14) {
                    if let legacy=ScreenSaverDefaults(forModuleWithName:"com.apple.screensaver") {
                        let previous=UserDefaults.standard.dictionary(forKey:"OceanPreviousLegacySaver") ?? [:]
                        if previous.isEmpty { legacy.removeObject(forKey:"moduleDict") } else { legacy.set(previous,forKey:"moduleDict") }
                        legacy.synchronize()
                    }
                    UserDefaults.standard.set(false,forKey:"OceanScreenSaverConfigured")
                    self.status("Previous screen saver restored");return
                }
                let original=try self.read(Data(contentsOf:self.backup)),before=try Data(contentsOf:self.store)
                let current=try self.read(before)
                let restored=Self.restoring(current,from:original,module:self.destination)
                let data=try PropertyListSerialization.data(fromPropertyList:restored,format:.binary,options:0)
                guard try Data(contentsOf:self.store)==before else { throw OceanFailure(message:"Wallpaper settings changed during restore") }
                try data.write(to:self.store,options:.atomic);self.reloadAgent()
                UserDefaults.standard.set(false,forKey:"OceanScreenSaverConfigured")
                self.status("Previous screen saver restored")
            } catch { self.status("Screen saver restore: \(error.localizedDescription)") }
        }
    }
    private func installed() throws -> URL {
        let fm=FileManager.default
        guard let source=Bundle.main.resourceURL?.appendingPathComponent("Ocean.saver"),
              Bundle(url:source)?.bundleIdentifier==Self.identifier else { throw OceanFailure(message:"Bundled Ocean screen saver is missing") }
        let executable="Contents/MacOS/OceanScreenSaver",signature="Contents/_CodeSignature/CodeResources"
        if fm.fileExists(atPath:destination.path) {
            guard Bundle(url:destination)?.bundleIdentifier==Self.identifier else { throw OceanFailure(message:"Another Ocean.saver already exists") }
            if try Data(contentsOf:source.appendingPathComponent(executable))==Data(contentsOf:destination.appendingPathComponent(executable)),
               try Data(contentsOf:source.appendingPathComponent(signature))==Data(contentsOf:destination.appendingPathComponent(signature)) { return destination }
        }
        try fm.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
        let incoming=destination.deletingLastPathComponent().appendingPathComponent(".Ocean-\(UUID().uuidString).saver")
        let previous=destination.deletingLastPathComponent().appendingPathComponent(".Ocean-previous-\(UUID().uuidString).saver")
        try fm.copyItem(at:source,to:incoming)
        let replacing=fm.fileExists(atPath:destination.path)
        if replacing { try fm.moveItem(at:destination,to:previous) }
        do { try fm.moveItem(at:incoming,to:destination) }
        catch { if replacing { try? fm.moveItem(at:previous,to:destination) };throw error }
        if replacing { try? fm.removeItem(at:previous) }
        UserDefaults.standard.set(true,forKey:"OceanSaverNeedsReload")
        return destination
    }
    private func enableLegacy(_ module: URL,force: Bool) throws {
        guard let legacy=ScreenSaverDefaults(forModuleWithName:"com.apple.screensaver") else { throw OceanFailure(message:"Screen saver preferences unavailable") }
        let previous=legacy.dictionary(forKey:"moduleDict") ?? [:]
        if UserDefaults.standard.bool(forKey:"OceanScreenSaverConfigured"),!force,previous["path"] as? String != module.path {
            status("Ocean saver updated; preserving your selected screen saver");return
        }
        if !UserDefaults.standard.bool(forKey:"OceanLegacySaverBackupSaved") {
            UserDefaults.standard.set(previous,forKey:"OceanPreviousLegacySaver")
            UserDefaults.standard.set(true,forKey:"OceanLegacySaverBackupSaved")
        }
        legacy.set(["moduleName":"Ocean","path":module.path,"type":0] as [String:Any],forKey:"moduleDict")
        guard legacy.synchronize(),legacy.dictionary(forKey:"moduleDict")?["path"] as? String==module.path else { throw OceanFailure(message:"Screen saver selection was not saved") }
        ready()
    }

    func enableIfNeeded(force: Bool = false) {
        queue.async {
            guard !self.configuring,(!self.attempted || force) else { return };self.attempted=true
            self.configuring=true
            var awaitingVerification=false
            defer { if !awaitingVerification { self.configuring=false } }
            guard UserDefaults.standard.object(forKey:"OceanAutomaticScreenSaver") as? Bool != false || force else { return }
            do {
                let module=try self.installed()
                if #unavailable(macOS 14) { try self.enableLegacy(module,force:force);return }
                let before=try Data(contentsOf:self.store),dictionary=try self.read(before)
                if let section=dictionary["AllSpacesAndDisplays"] as? [String:Any],Self.selectedModule(section)?.absoluteString==Self.canonicalModule(module).absoluteString {
                    self.ready();return
                }
                // Set up once. Later launches update our module without taking
                // over a different saver the user deliberately selected.
                if UserDefaults.standard.bool(forKey:"OceanScreenSaverConfigured"),!force { self.status("Ocean saver updated; preserving your selected screen saver");return }
                let selected=try Self.selecting(module,in:dictionary)
                let encoded=try PropertyListSerialization.data(fromPropertyList:selected,format:.binary,options:0)
                try FileManager.default.createDirectory(at:self.backup.deletingLastPathComponent(),withIntermediateDirectories:true)
                if !FileManager.default.fileExists(atPath:self.backup.path) { try before.write(to:self.backup,options:.atomic) }
                guard try Data(contentsOf:self.store)==before else { throw OceanFailure(message:"Wallpaper settings changed during setup; retry setup") }
                try encoded.write(to:self.store,options:.atomic)
                let previousAgents=self.reloadAgent()
                awaitingVerification=true
                self.queue.asyncAfter(deadline:.now()+3) {
                    defer { self.configuring=false }
                    do {
                        let currentData=try Data(contentsOf:self.store),current=try self.read(currentData)
                        var seen=0,matched=0
                        _=Self.sections(current) { section in
                            seen += 1
                            if Self.selectedModule(section)?.absoluteString==Self.canonicalModule(module).absoluteString { matched += 1 }
                            return section
                        }
                        let currentAgents=Set(NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.wallpaper.agent").map(\.processIdentifier))
                        guard seen>0,matched==seen,!previousAgents.isEmpty,currentAgents.isDisjoint(with:previousAgents),!currentAgents.isEmpty else {
                            // Only roll back our own unchanged write; don't overwrite
                            // another user's concurrent settings change.
                            if currentData==encoded { try before.write(to:self.store,options:.atomic);self.reloadAgent() }
                            throw OceanFailure(message:"macOS did not retain Ocean's screen saver selection")
                        }
                        UserDefaults.standard.set(true,forKey:"OceanAutomaticScreenSaver")
                        UserDefaults.standard.set(true,forKey:"OceanScreenSaverConfigured")
                        self.ready()
                    } catch { self.status("Screen saver setup: \(error.localizedDescription)") }
                }
            } catch { self.status("Screen saver setup: \(error.localizedDescription)") }
        }
    }
}
