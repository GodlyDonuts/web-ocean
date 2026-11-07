import Foundation
struct OceanFailure:LocalizedError { let message:String;var errorDescription:String? { message } }
@main struct NativeWallpaperSetupTests {
 static func main() throws {
    let originalSlot:[String:Any]=["Content":["Choices":[["Provider":"original","Configuration":Data([1,2,3])]]],"keep":9]
    let section:[String:Any]=["Desktop":originalSlot,"Idle":originalSlot,"Type":"individual","future":Data([7])]
    let original:[String:Any]=["AllSpacesAndDisplays":section,"SystemDefault":section,"Displays":["a":section],"Spaces":["s":["Default":section,"Displays":["b":section]]],"unknown":42]
    let selected=try NativeWallpaperSetup.selecting(in:original)
    precondition(NativeWallpaperSetup.selected(in:selected))
    var count=0
    _=AutomaticScreenSaverSetup.sections(selected) { s in
        precondition(s["future"] as? Data==Data([7]))
        let desktop=s["Desktop"] as! [String:Any],idle=s["Idle"] as! [String:Any]
        let dc=desktop["Content"] as! [String:Any],ic=idle["Content"] as! [String:Any]
        let options=try! PropertyListSerialization.propertyList(from:dc["EncodedOptionValues"] as! Data,format:nil) as! [String:Any]
        let values=options["values"] as! [String:Any]
        let picker=(values["placement"] as! [String:Any])["picker"] as! [String:Any]
        precondition((picker["_0"] as! [String:Any])["id"] as? String=="Crop")
        let color0=((values["color"] as! [String:Any])["color"] as! [String:Any])["_0"] as! [String:Any]
        let color=color0["color"] as! [String:Any]
        let space=try! PropertyListSerialization.propertyList(from:color["colorSpace"] as! Data,format:nil) as! String
        precondition(space=="kCGColorSpaceGenericRGB","WallpaperAgent requires nested binary-plist color space")
        let idleOptions=try! PropertyListSerialization.propertyList(from:ic["EncodedOptionValues"] as! Data,format:nil) as! [String:Any]
        precondition((idleOptions["values"] as! [String:Any]).isEmpty,"Idle must not inherit desktop placement")
        count += 1;return s
    }
    precondition(count==5)
    precondition((NativeWallpaperSetup.restoring(selected,from:original) as NSDictionary).isEqual(to:original))
    var changed=selected
    var top=changed["AllSpacesAndDisplays"] as! [String:Any]
    top["Desktop"]=originalSlot;changed["AllSpacesAndDisplays"]=top
    let restored=NativeWallpaperSetup.restoring(changed,from:original)
    precondition((restored as NSDictionary).isEqual(to:original),"A user's replacement desktop survives restoring the owned idle slot")
    var linked=original;linked["AllSpacesAndDisplays"]=["Linked":originalSlot,"Type":"linked","future":Data([8])]
    let live=try NativeWallpaperSetup.selecting(in:linked)
    precondition((NativeWallpaperSetup.restoring(live,from:linked) as NSDictionary).isEqual(to:linked))
    do { _=try NativeWallpaperSetup.selecting(in:[:]);fatalError("Unknown schema accepted") } catch {}
    print("PASS: native desktop/idle providers, distinct option wire formats, topology/unknown-field preservation, linked and partial restore; no OS writes")
 }
}
