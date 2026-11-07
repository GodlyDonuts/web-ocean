import Foundation

// The host can suspend a wallpaper during a lock transition. Only a physically
// sleeping/offline display is unconditionally non-drawable; visible locked
// presentation must not inherit desktop coverage or an old host pause.
enum OceanPresentation {
    static func shouldRender(displayAwake:Bool,hostSuspended:Bool,sessionLocked:Bool,presentationMode:String) -> Bool {
        displayAwake && (!hostSuspended || sessionLocked || presentationMode=="locked")
    }
    static func needsRecovery(oldMode:String,newMode:String,wasSuspended:Bool,isSuspended:Bool) -> Bool {
        (newMode=="locked" && oldMode != "locked") || (wasSuspended && !isSuspended) || (newMode=="locked" && wasSuspended != isSuspended)
    }
}
