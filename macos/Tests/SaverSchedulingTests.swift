import Foundation
@main struct SaverSchedulingTests {
 static func main() {
    // A preview has no authority to add a suspension reason. OS saver and
    // lock states are independent; stopping the saver must not clear a lock.
    var state=SurfaceSuspensionState()
    precondition(!state.isSuspended)
    state.set(.screenSaver,active:true);state.set(.screenLocked,active:true)
    state.set(.screenSaver,active:false);precondition(state.isSuspended)
    state.set(.screenLocked,active:false);precondition(!state.isSuspended)
    for rate in [6,15,20,24,30] {
        var cadence=FrameSubmissionCadence(),count=0
        for tick in 0..<600 { if cadence.shouldSubmit(at:Double(tick)/60,framesPerSecond:rate) { count += 1 } }
        precondition(abs(count-rate*10)<=1,"Host callbacks must not override the selected cadence")
        precondition(cadence.shouldSubmit(at:100,framesPerSecond:rate))
        precondition(!cadence.shouldSubmit(at:100,framesPerSecond:rate),"No replay burst after a stall")
        precondition(cadence.shouldSubmit(at:0,framesPerSecond:rate),"Clock rollback recovers")
    }
    print("PASS: independent OS saver/lock suspension, cadence limits and stall/clock recovery")
 }
}
