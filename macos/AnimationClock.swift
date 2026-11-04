import Foundation
import simd

// Wave frequencies are integer multiples of 2*pi/600. Detail advection and
// procedural clouds are not periodic over that interval and must not reset.
struct AnimationClock {
    enum Mode: String { case continuous, legacy, unwrapped }
    private(set) var elapsed: Double
    private var legacyTime: Float
    let mode: Mode
    static let wavePeriod = 600.0
    static let cloudShiftCount = 14 // warp, seven low octaves, six high octaves

    init(start: Double = 0, mode: Mode = .continuous) {
        elapsed = start.isFinite ? max(0,min(start,1e12)) : 0
        legacyTime = Float(elapsed)
        self.mode = mode
    }
    mutating func advance(by delta: Double) {
        guard delta.isFinite && delta >= 0 else { return }
        elapsed = min(1e12,elapsed+delta)
        if mode == .legacy { legacyTime = (legacyTime+Float(delta)).truncatingRemainder(dividingBy:600) }
    }
    var waveTime: Float {
        if mode == .legacy { return legacyTime }
        return Float(elapsed.truncatingRemainder(dividingBy:Self.wavePeriod))
    }
    var detailTime: Float { mode == .unwrapped ? Float(elapsed) : waveTime }
    var stableDetails: Bool { mode == .continuous && elapsed >= Self.wavePeriod }

    static func fraction(_ value: Double) -> Float { Float(value-floor(value)) }
    // Integer octave ratios in the shader preserve these independent wraps.
    static func volumetricCloudPhases(time: Double, velocity: SIMD2<Double>) -> [Float] {
        let drift = -velocity*time
        return [fraction(drift.x*0.09),fraction(drift.y*0.09),
                fraction(drift.x*0.018),fraction(drift.y*0.018),
                fraction(time*0.000041),fraction(-time*0.000027),
                fraction(drift.x*0.022*1.4),fraction(drift.y*0.009*1.4)]
    }
    func detailPhases(wind: SIMD2<Float>) -> SIMD4<Float> {
        SIMD4(Self.fraction(elapsed*Double(Float(0.0004))*Double(wind.x)),
              Self.fraction(elapsed*Double(Float(0.0004))*Double(wind.y)),
              Self.fraction(elapsed*Double(Float(0.013))),1)
    }

    // Bounded fractional coordinates plus wrapping 32-bit lattice origins keep
    // the PCG noise hash deterministic without large floating-point positions.
    private static func storeSplit(_ position: SIMD2<Double>, to words: UnsafeMutableBufferPointer<UInt32>, at index: Int) {
        precondition(index+4<=words.count)
        for axis in 0..<2 {
            let whole = floor(position[axis])
            var fraction = Float(position[axis]-whole)
            var origin = UInt32(truncatingIfNeeded:Int64(whole.truncatingRemainder(dividingBy:4294967296)))
            if fraction >= 1 { origin &+= 1; fraction = 0 }
            words[index+axis] = fraction.bitPattern
            words[index+axis+2] = origin
        }
    }
    static func split(_ position: SIMD2<Double>) -> [UInt32] {
        Array(unsafeUninitializedCapacity:4) { words,count in
            storeSplit(position,to:words,at:0); count = 4
        }
    }
    func writeCloudShifts(to words: UnsafeMutableBufferPointer<UInt32>) {
        precondition(words.count==Self.cloudShiftCount*4)
        let low = SIMD2<Double>(Double(Float(0.004)),Double(Float(0.0012)))*elapsed
        Self.storeSplit(low*Double(Float(0.3)),to:words,at:0)
        var index = 4
        func appendOctaves(_ start: SIMD2<Double>, count: Int) {
            var offset = start
            let a = Double(Float(0.8)), b = Double(Float(0.6)), scale = Double(Float(2.03))
            for _ in 0..<count {
                Self.storeSplit(offset,to:words,at:index); index += 4
                offset = SIMD2(a*offset.x-b*offset.y,b*offset.x+a*offset.y)*scale
            }
        }
        appendOctaves(low*SIMD2(1,Double(Float(1.7))),count:7)
        appendOctaves(SIMD2(Double(Float(0.0015))*elapsed,0),count:6)
    }
    func cloudShiftWords() -> [UInt32] {
        Array(unsafeUninitializedCapacity:Self.cloudShiftCount*4) { words,count in
            writeCloudShifts(to:words); count = words.count
        }
    }
}
