import AppKit
import CryptoKit

// Current macOS wallpaper-extension compatibility layer. Preserve unknown
// store fields and back up before changing Ocean-owned desktop/idle choices.
final class NativeWallpaperSetup {
    static let identifier="local.wallpaper.ocean.live"
    static var moduleURL:URL? {
        guard #available(macOS 26,*),let url=Bundle.main.builtInPlugInsURL?.appendingPathComponent("OceanLiveWallpaper.appex"),Bundle(url:url)?.bundleIdentifier==identifier else { return nil }
        return url
    }
    var onStatus:((String)->Void)?
    var onReady:(()->Void)?
    private let queue=DispatchQueue(label:"Ocean.native-wallpaper-setup",qos:.utility)
    private(set) var verified=false
    private var attempted=false
    private var configuring=false
    private let store=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    private let backup=CelestialCycle.supportDirectory.appendingPathComponent("before-ocean-screensaver.plist")
    static func provider(_ slot:[String:Any]?) -> String? {
        ((slot?["Content"] as? [String:Any])?["Choices"] as? [[String:Any]])?.first?["Provider"] as? String
    }
    static func selected(in dictionary:[String:Any]) -> Bool {
        var seen=0,matching=0
        _=AutomaticScreenSaverSetup.sections(dictionary) { section in
            seen += 1
            if provider(section["Desktop"] as? [String:Any])==identifier && provider(section["Idle"] as? [String:Any])==identifier { matching += 1 }
            return section
        }
        return seen>0 && seen==matching
    }
    static func selecting(in dictionary:[String:Any]) throws -> [String:Any] {
        guard dictionary["AllSpacesAndDisplays"] is [String:Any],dictionary["SystemDefault"] is [String:Any] else { throw OceanFailure(message:"Unknown wallpaper store format") }
        let colorSpace=try PropertyListSerialization.data(fromPropertyList:"kCGColorSpaceGenericRGB",format:.binary,options:0)
        let desktopOptions:[String:Any] = ["values":[
            "placement":["picker":["_0":["id":"Crop"]]],
            "color":["color":["_0":["color":["components":[0.0,0,0,1],"colorSpace":colorSpace]]]]]]
        let desktop=try PropertyListSerialization.data(fromPropertyList:desktopOptions,format:.binary,options:0)
        let idle=try PropertyListSerialization.data(fromPropertyList:["values":[String:Any]()],format:.binary,options:0)
        func slot(_ options:Data) -> [String:Any] {
            ["Content":["Choices":[["Provider":identifier,"Configuration":Data("ocean".utf8),"Files":[Any]()] as [String:Any]],"Shuffle":"$null","EncodedOptionValues":options],"LastSet":Date(),"LastUse":Date()]
        }
        return AutomaticScreenSaverSetup.sections(dictionary) { previous in
            var section=previous;section.removeValue(forKey:"Linked")
            section["Desktop"]=slot(desktop);section["Idle"]=slot(idle);section["Type"]="individual"
            return section
        }
    }
    static func restoring(_ current:[String:Any],from previous:[String:Any]) -> [String:Any] {
        func visit(_ now:[String:Any],_ old:[String:Any]) -> [String:Any] {
            var next=now
            let desktopOwned=provider(now["Desktop"] as? [String:Any])==identifier
            let idleOwned=provider(now["Idle"] as? [String:Any])==identifier
            if desktopOwned && idleOwned {
                for key in ["Desktop","Idle","Linked","Type"] { next[key]=old[key] }
                return next
            }
            if desktopOwned || idleOwned {
                if desktopOwned { next["Desktop"]=old["Desktop"] ?? old["Linked"] }
                if idleOwned { next["Idle"]=old["Idle"] ?? old["Linked"] }
                return next
            }
            for (key,value) in now { if let child=value as? [String:Any] { next[key]=visit(child,old[key] as? [String:Any] ?? [:]) } }
            return next
        }
        return visit(current,previous)
    }
    private func status(_ text:String) { DispatchQueue.main.async { self.onStatus?(text) } }
    private func dictionary(_ data:Data) throws -> [String:Any] {
        guard let value=try PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any] else { throw OceanFailure(message:"Invalid wallpaper store") };return value
    }
    private func restartAgent() -> Set<pid_t> {
        var previous=Set<pid_t>()
        DispatchQueue.main.sync {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.wallpaper.agent") where app.bundleURL?.path=="/System/Library/CoreServices/WallpaperAgent.app" {
                previous.insert(app.processIdentifier)
                if !app.terminate() { app.forceTerminate() }
            }
        }
        return previous
    }
    private func processRunning(_ module:URL) -> Bool {
        let expected=module.appendingPathComponent("Contents/MacOS/OceanLiveWallpaper").path
        let process=Process(),pipe=Pipe()
        process.executableURL=URL(fileURLWithPath:"/bin/ps");process.arguments=["-axo","uid=,pid=,comm="]
        process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
        do {
            try process.run()
            let data=pipe.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
            return String(data:data,encoding:.utf8)?.split(separator:"\n").contains { line in
                let fields=line.split(maxSplits:2,whereSeparator:{ $0.isWhitespace })
                return fields.count==3 && fields[0]==String(getuid()) && fields[2]==expected
            } ?? false
        } catch { return false }
    }
    private func ready(_ fingerprint:String) {
        DispatchQueue.main.async {
            self.verified=true
            UserDefaults.standard.set(true,forKey:"OceanNativeWallpaper")
            UserDefaults.standard.set(true,forKey:"OceanNativeWallpaperConfigured")
            UserDefaults.standard.set(fingerprint,forKey:"OceanNativeWallpaperFingerprint")
            self.onStatus?("Live Ocean desktop and lock screen selected");self.onReady?()
        }
    }
    func enable(force:Bool=false) {
        queue.async {
            guard !self.configuring,(!self.attempted || force),let module=Self.moduleURL else { return }
            if let session=CGSessionCopyCurrentDictionary() as? [String:Any],(session["CGSSessionScreenIsLocked"] as? Bool)==true { self.status("Live Ocean setup pending unlock");return }
            self.attempted=true;self.configuring=true
            do {
                let register=Process();register.executableURL=URL(fileURLWithPath:"/usr/bin/pluginkit");register.arguments=["-a",module.path]
                register.standardOutput=FileHandle.nullDevice;register.standardError=FileHandle.nullDevice
                try register.run();register.waitUntilExit()
                guard register.terminationStatus==0 else { throw OceanFailure(message:"Wallpaper extension registration failed") }
                let binary=try Data(contentsOf:module.appendingPathComponent("Contents/MacOS/OceanLiveWallpaper"))
                let fingerprint=SHA256.hash(data:binary).map { String(format:"%02x",$0) }.joined()
                let before=try Data(contentsOf:self.store),current=try self.dictionary(before)
                let alreadySelected=Self.selected(in:current)
                if alreadySelected,self.processRunning(module),UserDefaults.standard.string(forKey:"OceanNativeWallpaperFingerprint")==fingerprint { self.configuring=false;self.ready(fingerprint);return }
                if !alreadySelected,UserDefaults.standard.bool(forKey:"OceanNativeWallpaperConfigured"),!force {
                    UserDefaults.standard.set(false,forKey:"OceanNativeWallpaper");self.configuring=false
                    self.status("Preserving your chosen wallpaper; Ocean live setup is available in the menu");return
                }
                let next=try Self.selecting(in:current)
                let encoded=try PropertyListSerialization.data(fromPropertyList:next,format:.binary,options:0)
                try FileManager.default.createDirectory(at:self.backup.deletingLastPathComponent(),withIntermediateDirectories:true)
                if !FileManager.default.fileExists(atPath:self.backup.path) { try before.write(to:self.backup,options:.atomic) }
                guard try Data(contentsOf:self.store)==before else { throw OceanFailure(message:"Wallpaper settings changed during setup") }
                try encoded.write(to:self.store,options:.atomic)
                let previousAgents=self.restartAgent()
                self.queue.asyncAfter(deadline:.now()+4) {
                    defer { self.configuring=false }
                    do {
                        let currentData=try Data(contentsOf:self.store),current=try self.dictionary(currentData)
                        let agents=Set(NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.wallpaper.agent").map(\.processIdentifier))
                        guard Self.selected(in:current),!agents.isEmpty,agents.isDisjoint(with:previousAgents),self.processRunning(module) else {
                            let restored=Self.restoring(current,from:try self.dictionary(before))
                            if !(restored as NSDictionary).isEqual(to:current),try Data(contentsOf:self.store)==currentData {
                                try PropertyListSerialization.data(fromPropertyList:restored,format:.binary,options:0).write(to:self.store,options:.atomic)
                                _ = self.restartAgent()
                            }
                            throw OceanFailure(message:"macOS rejected the live Ocean wallpaper")
                        }
                        self.ready(fingerprint)
                    } catch { UserDefaults.standard.set(false,forKey:"OceanNativeWallpaper");self.status(error.localizedDescription) }
                }
            } catch { self.configuring=false;self.status(error.localizedDescription) }
        }
    }
    func restore(completion:@escaping(Bool)->Void) {
        queue.async {
            var success=false
            defer { let restored=success;DispatchQueue.main.async { completion(restored) } }
            do {
                let before=try Data(contentsOf:self.store),current=try self.dictionary(before),previous=try self.dictionary(Data(contentsOf:self.backup))
                let restored=Self.restoring(current,from:previous)
                guard try Data(contentsOf:self.store)==before else { throw OceanFailure(message:"Wallpaper settings changed during restore") }
                try PropertyListSerialization.data(fromPropertyList:restored,format:.binary,options:0).write(to:self.store,options:.atomic)
                _ = self.restartAgent();UserDefaults.standard.set(false,forKey:"OceanNativeWallpaper");success=true
            } catch { self.status("Restore live wallpaper: \(error.localizedDescription)") }
        }
    }
}
