import Foundation

@main struct ViewportLayoutTests {
    static func main() {
        let cases: [(Double,Double,Double)] = [
            (1200,750,2),(1280,800,1),(1920,1080,1),(3840,2160,1),
            (5120,2880,1),(7680,4320,1),(3440,1440,1),(5120,1440,1),
            (1080,1920,1),(2160,3840,1),(640,400,2),(2560,1600,1.5),
            (30000,100,2),(100,30000,2),(1000000,20,1),(20,1000000,1)
        ]
        for (w,h,scale) in cases {
            let l = ViewportLayout(pointWidth:w,pointHeight:h,backingScale:scale)
            precondition(l.width > 0 && l.height > 0 && l.width <= 16384 && l.height <= 16384)
            let target = w/h
            // One-pixel rounding/clamping is unavoidable for pathological ratios.
            precondition(abs(Double(l.width)-target*Double(l.height)) <= 1+target, "Aspect ratio changed for \(w)x\(h)")
            precondition(l.width*l.height <= 1280*800+l.width+l.height)
            precondition(Double(l.columns)/Double(l.width) >= 256.0/1280)
            precondition(Double(l.rows)/Double(l.height) >= 192.0/800)
            print("\(Int(w))x\(Int(h)) @\(scale): \(l.width)x\(l.height), mesh \(l.columns)x\(l.rows)")
        }
        let standard = ViewportLayout(pointWidth:1200,pointHeight:750,backingScale:2)
        precondition(standard.width == 1280 && standard.height == 800 && standard.columns == 256 && standard.rows == 192)
        print("PASS: viewport budget, aspect ratio, and mesh density across \(cases.count) display layouts.")
    }
}
