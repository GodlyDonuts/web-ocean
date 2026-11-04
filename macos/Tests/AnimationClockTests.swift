import Foundation
import simd

@main struct AnimationClockTests {
    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) {
        precondition(abs(a-b)<=tolerance,"\(a) differs from \(b)")
    }
    static func phaseDelta(_ a: Float, _ b: Float) -> Double {
        var delta = Double(a)-Double(b)
        if delta < -0.5 { delta += 1 }; if delta > 0.5 { delta -= 1 }
        return delta
    }
    static func main() {
        var clock = AnimationClock(start:599.99)
        precondition(!clock.stableDetails)
        clock.advance(by:0.02)
        precondition(clock.stableDetails)
        near(Double(clock.waveTime),0.01)
        near(clock.elapsed,600.01,1e-10)
        var old = AnimationClock(start:599.99,mode:.legacy)
        old.advance(by:0.02)
        precondition(!old.stableDetails && old.waveTime<0.02)
        let wind = SIMD2<Float>(0.6,-0.8)
        for uptime in [600.0,86400.0,30*86400.0,365*86400.0] {
            var c = AnimationClock(start:uptime)
            let before = c.detailPhases(wind:wind)
            c.advance(by:1.0/30)
            let after = c.detailPhases(wind:wind)
            for axis in 0..<3 {
                let rate = axis==2 ? Double(Float(0.013)) : Double(wind[axis])*Double(Float(0.0004))
                near(phaseDelta(after[axis],before[axis]),rate/30,1.2e-7)
            }
            near(c.elapsed-uptime,1.0/30,1e-8)
            precondition(c.waveTime.isFinite && c.waveTime>=0 && c.waveTime<=600)
        }
        let time = 30*86400.0
        let words = AnimationClock(start:time).cloudShiftWords()
        precondition(words.count==AnimationClock.cloudShiftCount*4)
        let a = Double(Float(0.8)), b = Double(Float(0.6)), scale = Double(Float(2.03))
        let radius = hypot(a,b)*scale, angle = atan2(b,a)
        let low = SIMD2<Double>(Double(Float(0.004))*time,Double(Float(0.0012))*time)
        var expected = [low*Double(Float(0.3))]
        for (start,count) in [(low*SIMD2(1,Double(Float(1.7))),7),(SIMD2(Double(Float(0.0015))*time,0),6)] {
            for octave in 0..<count {
                let c = cos(Double(octave)*angle), s = sin(Double(octave)*angle)
                expected.append(SIMD2(c*start.x-s*start.y,s*start.x+c*start.y)*pow(radius,Double(octave)))
            }
        }
        for (index,point) in expected.enumerated() {
            for axis in 0..<2 {
                let fraction = Float(bitPattern:words[index*4+axis])
                precondition(fraction>=0 && fraction<1)
                let origin = Int32(bitPattern:words[index*4+axis+2])
                near(Double(origin)+Double(fraction),point[axis],1e-7)
            }
        }
        for point in [SIMD2<Double>(-0.00000001,0.999999999),SIMD2(4294967296.25,-4294967296.75)] {
            let split = AnimationClock.split(point)
            precondition(Float(bitPattern:split[0])>=0 && Float(bitPattern:split[0])<1)
            precondition(Float(bitPattern:split[1])>=0 && Float(bitPattern:split[1])<1)
        }
        let modulo = AnimationClock.split(SIMD2(4294967296.25,-4294967296.75))
        precondition(modulo[2]==0 && modulo[3]==UInt32.max)
        precondition(AnimationClock(start:.infinity).elapsed==0)
        var invalid = AnimationClock(); invalid.advance(by:.nan); invalid.advance(by:-1)
        precondition(invalid.elapsed==0)
        let velocity = SIMD2<Double>(-0.0033,0.0062)
        for t in [0.0,599.99,600.01,2592000,31536000] {
            let a=AnimationClock.volumetricCloudPhases(time:t,velocity:velocity)
            let b=AnimationClock.volumetricCloudPhases(time:t+0.01,velocity:velocity)
            precondition(a.count==8 && a.allSatisfy { $0>=0 && $0<1 })
            for i in 0..<8 { precondition(abs(phaseDelta(a[i],b[i]))<0.00002) }
        }
        let still=AnimationClock.volumetricCloudPhases(time:30,velocity:.zero)
        precondition(still[0]==0 && still[1]==0 && still[4]>0)
        print("PASS: wave period, continuous detail phases through one year, 14 cloud lattice shifts against independent complex-power coordinates, and bounded continuous volumetric advection/evolution phases.")
    }
}
