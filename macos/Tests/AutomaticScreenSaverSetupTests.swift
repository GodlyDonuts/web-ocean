import Foundation
struct OceanFailure: LocalizedError { let message:String;var errorDescription:String? { message } }
@main struct AutomaticScreenSaverSetupTests {
 static func main() throws {
    let module=URL(fileURLWithPath:"/Users/example/Library/Screen Savers/Ocean.saver")
    precondition(!AutomaticScreenSaverSetup.canonicalModule(URL(fileURLWithPath:module.path,isDirectory:true)).absoluteString.hasSuffix("/"),"Settings identifies the saver without a trailing slash")
    let oldSlot:[String:Any] = ["Content":["Choices":[["Provider":"original","Configuration":Data([1,2,3])]]],"keep":"original"]
    let section:[String:Any] = ["Desktop":oldSlot,"Idle":oldSlot,"Type":"individual","future-field":42]
    let original:[String:Any] = ["AllSpacesAndDisplays":section,"SystemDefault":section,
      "Displays":["display-a":section],"Spaces":["space-a":["Default":section,"Displays":["display-b":section]]],"Unknown":Data([5,6,7])]
    let selected=try AutomaticScreenSaverSetup.selecting(module,in:original)
    var count=0
    _=AutomaticScreenSaverSetup.sections(selected) { result in
        precondition(AutomaticScreenSaverSetup.selectedModule(result)==module)
        precondition((result["Desktop"] as! NSDictionary).isEqual(to:oldSlot))
        precondition(result["future-field"] as? Int==42)
        count += 1;return result
    }
    precondition(count==5)
    precondition(selected["Unknown"] as? Data==Data([5,6,7]))
    let restored=AutomaticScreenSaverSetup.restoring(selected,from:original,module:module)
    precondition((restored as NSDictionary).isEqual(to:original),"Restoring preserves all original per-display/Space selections")
    let untouched=AutomaticScreenSaverSetup.restoring(original,from:original,module:module)
    precondition((untouched as NSDictionary).isEqual(to:original),"Do not take over another selected saver")
    var linked=original;linked["AllSpacesAndDisplays"]=["Linked":oldSlot,"Type":"linked"]
    let next=try AutomaticScreenSaverSetup.selecting(module,in:linked)
    let converted=next["AllSpacesAndDisplays"] as! [String:Any]
    precondition(converted["Linked"]==nil)
    precondition((converted["Desktop"] as! NSDictionary).isEqual(to:oldSlot),"Linked wallpaper preserved when separating idle slot")
    do { _=try AutomaticScreenSaverSetup.selecting(module,in:[:]);fatalError("Unknown format must fail closed") } catch {}
    print("PASS: automatic saver store selection/restore, all display/Space scopes, unknown fields, linked wallpaper, unknown schema; no OS writes")
 }
}
