import Foundation
@main struct ProductPolicyTests {
    static func main() throws {
        let home=URL(fileURLWithPath:"/Users/test")
        precondition(OceanProduct.isInstalled(URL(fileURLWithPath:"/Applications/Ocean.app"),home:home))
        precondition(OceanProduct.isInstalled(URL(fileURLWithPath:"/Users/test/Applications/Ocean.app"),home:home))
        for path in ["/Volumes/Ocean/Ocean.app","/Applications-backup/Ocean.app","/Users/test/Downloads/Ocean.app","/Applications/../tmp/Ocean.app"] {
            precondition(!OceanProduct.isInstalled(URL(fileURLWithPath:path),home:home))
        }
        precondition(OceanProduct.needsWelcome(enabled:nil,completed:false,previouslyConfigured:false))
        precondition(!OceanProduct.needsWelcome(enabled:nil,completed:false,previouslyConfigured:true))
        precondition(OceanProduct.needsWelcome(enabled:false,completed:true,previouslyConfigured:true))
        precondition(!OceanProduct.needsWelcome(enabled:true,completed:true,previouslyConfigured:true))
        precondition(OceanProduct.needsWelcome(enabled:true,completed:false,previouslyConfigured:false))
        precondition(OceanProduct.qualityIndex(fps:0,pixels:1024000)==1)
        precondition(OceanProduct.qualityIndex(fps:60,pixels:1024000)==3)
        let legacy=try JSONDecoder().decode(LiveWallpaperControl.self,from:Data(#"{"framesPerSecond":0,"pixelBudget":1024000}"#.utf8))
        precondition(!legacy.userPaused && legacy.requestedFPS==0,"Desktop coverage pause cannot become a user pause or a frame-rate preference")
        let user=LiveWallpaperControl(framesPerSecond:24,pixelBudget:1024000,userPaused:true,requestedFPS:20)
        let roundTrip=try JSONDecoder().decode(LiveWallpaperControl.self,from:JSONEncoder().encode(user))
        precondition(roundTrip==user)
        precondition(OceanPresentation.frameRate(policy:24,userPaused:true)==0)
        precondition(OceanPresentation.frameRate(policy:24,userPaused:false)==24)
        precondition(OceanPresentation.frameRate(policy:0,userPaused:false)==0)
        precondition(OceanPresentation.requestedRate(desktop:0,preference:20,fullScreen:true)==20)
        precondition(OceanPresentation.requestedRate(desktop:0,preference:20,fullScreen:false)==0)
        precondition(OceanPresentation.requestedRate(desktop:0,preference:0,fullScreen:true)==0)
        print("PASS: install locations, welcome/upgrade/disabled states, power presets, backward-compatible pause wire format and explicit pause policy")
    }
}
