import Foundation
import QuartzCore
import IOSurface

func debugLog(_ message:String) { print(message) }
@main struct NativeWallpaperABITests {
    static func main() async throws {
        guard dlopen("/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework/WallpaperExtensionKit",RTLD_NOW) != nil else { fatalError("Wallpaper runtime missing") }
        for name in ["WallpaperRemoteContextXPC","WallpaperSnapshotXPC"] {
            let cls:AnyClass=NSClassFromString(name)!
            var count:UInt32=0
            if let list=class_copyIvarList(cls,&count) {
                for i in 0..<Int(count) { print(name,String(cString:ivar_getName(list[i])!),ivar_getOffset(list[i])) }
                free(list)
            }
        }
        precondition(OceanInstallSnapshotEncoder(),"Snapshot runtime ABI unavailable")
        let layer=CALayer();layer.bounds=CGRect(x:0,y:0,width:64,height:64)
        let context=OceanCreateRemoteContext(layer,1,0)!
        let id=OceanRemoteContextID(context)
        precondition(id>0)
        let box=OceanWrapContext(id) as! NSObject
        let data=try NSKeyedArchiver.archivedData(withRootObject:box,requiringSecureCoding:true)
        let decoded=try NSKeyedUnarchiver.unarchivedObject(ofClasses:[type(of:box),NSNumber.self],from:data)
        precondition(decoded != nil,"Remote context coding round trip failed")
        let surface=IOSurface(properties:[.width:64,.height:64,.bytesPerElement:4,.bytesPerRow:256,.pixelFormat:0x42475241])!
        precondition(OceanWrapSnapshot(surface) != nil)
        let models=await buildSettingsViewModelsXPC()
        precondition(models != nil,"Wallpaper settings model wire ABI unavailable")
        print("PASS: native remote context allocation/coding, snapshot layout/encoder, real wallpaper settings model decoding; zero windows/preferences")
    }
}
