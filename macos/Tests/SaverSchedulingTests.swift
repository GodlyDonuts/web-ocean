import Foundation
@main struct SaverSchedulingTests {
 static func main() {
    var tracker=SaverActivityTracker()
    precondition(!tracker.isActive(at:0))
    tracker.rendered(token:"preview",at:1);tracker.rendered(token:"full",at:5)
    tracker.stopped(token:"preview");precondition(tracker.isActive(at:13))
    precondition(!tracker.isActive(at:17),"Crashed hosts expire without freezing wallpaper")
    tracker.rendered(token:"",at:20);precondition(!tracker.isActive(at:20))
    var state=SurfaceSuspensionState()
    state.set(.screenSaver,active:true);state.set(.saverRendering,active:true)
    state.set(.screenSaver,active:false);precondition(state.isSuspended)
    state.set(.saverRendering,active:false);precondition(!state.isSuspended)
    for rate in [6,15,20,24,30] {
        var cadence=FrameSubmissionCadence(),count=0
        for tick in 0..<600 { if cadence.shouldSubmit(at:Double(tick)/60,framesPerSecond:rate) { count += 1 } }
        precondition(abs(count-rate*10)<=1,"Host callbacks must not override the selected cadence")
        precondition(cadence.shouldSubmit(at:100,framesPerSecond:rate))
        precondition(!cadence.shouldSubmit(at:100,framesPerSecond:rate),"No replay burst after a stall")
        precondition(cadence.shouldSubmit(at:0,framesPerSecond:rate),"Clock rollback recovers")
    }
    print("PASS: independent saver leases, crash expiry, cadence limits and stall/clock recovery")
 }
}
