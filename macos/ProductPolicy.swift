import Foundation

enum OceanProduct {
    static let releases=URL(string:"https://github.com/GodlyDonuts/web-ocean/releases")!
    static let issues=URL(string:"https://github.com/GodlyDonuts/web-ocean/issues")!
    struct Quality:Equatable {
        let title:String
        let fps:Int
        let pixels:Double
    }
    static let qualities=[Quality(title:"Save Energy",fps:20,pixels:700000),
                          Quality(title:"Balanced",fps:0,pixels:1024000),
                          Quality(title:"Sharper",fps:30,pixels:2000000)]
    static func qualityIndex(fps:Int,pixels:Double)->Int {
        qualities.firstIndex { $0.fps==fps && abs($0.pixels-pixels)<1 } ?? qualities.count
    }
    static func isInstalled(_ url:URL,home:URL=FileManager.default.homeDirectoryForCurrentUser)->Bool {
        let path=url.standardizedFileURL.resolvingSymlinksInPath().path
        let roots=["/Applications/",home.appendingPathComponent("Applications").standardizedFileURL.path+"/"]
        return url.pathExtension=="app" && roots.contains { path.hasPrefix($0) }
    }
    static func needsWelcome(enabled:Bool?,completed:Bool,previouslyConfigured:Bool)->Bool {
        if let enabled { return !enabled || !completed }
        return !previouslyConfigured
    }
}
