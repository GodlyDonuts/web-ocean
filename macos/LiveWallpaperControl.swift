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
    var userPaused:Bool=false
    var requestedFPS:Int=0 // User preference, independent of desktop coverage.
    enum CodingKeys:String,CodingKey { case framesPerSecond,pixelBudget,userPaused,requestedFPS }
    init(framesPerSecond:Int,pixelBudget:Double,userPaused:Bool=false,requestedFPS:Int=0) {
        self.framesPerSecond=framesPerSecond;self.pixelBudget=pixelBudget;self.userPaused=userPaused;self.requestedFPS=requestedFPS
    }
    init(from decoder:Decoder)throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        framesPerSecond=try c.decode(Int.self,forKey:.framesPerSecond)
        pixelBudget=try c.decode(Double.self,forKey:.pixelBudget)
        userPaused=try c.decodeIfPresent(Bool.self,forKey:.userPaused) ?? false
        requestedFPS=try c.decodeIfPresent(Int.self,forKey:.requestedFPS) ?? 0
    }
    private static var lastPublished:Self?
    static func publish(framesPerSecond:Int,pixelBudget:Double,userPaused:Bool=false,requestedFPS:Int=0) {
        let value=Self(framesPerSecond:framesPerSecond,pixelBudget:pixelBudget,userPaused:userPaused,requestedFPS:requestedFPS)
        guard value != lastPublished,let data=try? JSONEncoder().encode(value) else { return }
        LiveWallpaperFiles.write(data,name:"playback.json");lastPublished=value
    }
    static func read() -> Self? {
        guard let data=try? Data(contentsOf:LiveWallpaperFiles.directory.appendingPathComponent("playback.json")),data.count<1024,
              let value=try? JSONDecoder().decode(Self.self,from:data),(0...120).contains(value.framesPerSecond),(0...120).contains(value.requestedFPS),
              value.pixelBudget.isFinite,(64000...8388608).contains(value.pixelBudget) else { return nil }
        return value
    }
}
