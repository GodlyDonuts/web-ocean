import Foundation
import simd
@main enum CloudMorphologyTests {
    static func main() {
        let fair=CloudMorphology.weights(.fair)
        let overcast=CloudMorphology.weights(OceanWeather(rain:0,cloud:1,wind:7,direction:118,thunder:0,mist:0))
        let rain=CloudMorphology.weights(.storm(0.4)),storm=CloudMorphology.weights(.storm(1))
        precondition(fair.x==0 && fair.y>0 && fair.w==0)
        precondition(overcast.x>0.8 && overcast.z>0.7 && overcast.w==0)
        precondition(rain.x>0.9 && rain.w==0 && storm.w==1 && storm.x==0)
        var previous=CloudMorphology.weights(.storm(0))
        for i in 0...10000 {
            let t=Double(i)/10000
            let w=CloudMorphology.weights(OceanWeather(rain:t,cloud:0.4+0.6*t,wind:7+38*t,direction:118,thunder:t,mist:t))
            for c in 0..<4 { precondition(w[c].isFinite && (0...1).contains(w[c]) && abs(w[c]-previous[c])<0.002) }
            previous=w
        }
        for kind in CloudMorphology.Kind.allCases {
            let w=CloudMorphology.weights(.fair,kind:kind)
            precondition((0..<4).allSatisfy{(0...1).contains(w[$0])})
            if let c=CloudMorphology.coverage(kind) { precondition((0...1).contains(c.low) && (0...1).contains(c.high)) }
        }
        print("PASS: fair/layered/rain/convective mixtures, all morphology overrides and 10,001 continuous weather states")
    }
}
