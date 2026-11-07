import Foundation
import Darwin

// Only Ocean's small, non-secret environment/control cache crosses the native
// wallpaper sandbox. The extension has read-only access to this one directory.
enum LiveWallpaperFiles {
    static var directory:URL {
        let home=getpwuid(getuid()).flatMap { $0.pointee.pw_dir }.map { String(cString:$0) } ?? NSHomeDirectory()
        return URL(fileURLWithPath:home).appendingPathComponent("Library/Caches/OceanWallpaperLive",isDirectory:true)
    }
    static func write(_ data:Data,name:String) {
        do {
            let fm=FileManager.default
            try fm.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let url=directory.appendingPathComponent(name)
            if (try? Data(contentsOf:url))==data { return }
            try data.write(to:url,options:.atomic)
            try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        } catch { NSLog("Ocean live cache: %@",error.localizedDescription) }
    }
}
struct LiveWallpaperControl:Codable,Equatable {
    var framesPerSecond:Int
    var pixelBudget:Double
    private static var lastPublished:Self?
    static func publish(framesPerSecond:Int,pixelBudget:Double) {
        let value=Self(framesPerSecond:framesPerSecond,pixelBudget:pixelBudget)
        guard value != lastPublished,let data=try? JSONEncoder().encode(value) else { return }
        LiveWallpaperFiles.write(data,name:"playback.json");lastPublished=value
    }
    static func read() -> Self? {
        guard let data=try? Data(contentsOf:LiveWallpaperFiles.directory.appendingPathComponent("playback.json")),data.count<1024,
              let value=try? JSONDecoder().decode(Self.self,from:data),(0...120).contains(value.framesPerSecond),
              value.pixelBudget.isFinite,(64000...8388608).contains(value.pixelBudget) else { return nil }
        return value
    }
}
