import Foundation
import CoreGraphics
@main struct RegionalRenderingTests {
    static func main() {
        func check(_ value:Bool,_ why:String) { precondition(value,why) }
        for (w,h) in [(1280,800),(1279,799),(400,1200),(1400,400),(1,1)] {
            let full=CGRect(x:0,y:0,width:w,height:h)
            check(RegionalRendering.hdrSupport(output:full,width:w,height:h)==full,"full remains full")
            for rect in [CGRect(x:0,y:0,width:0.05,height:1),CGRect(x:0.95,y:0,width:0.05,height:1),
                         CGRect(x:0,y:0,width:1,height:0.05),CGRect(x:0,y:0.95,width:1,height:0.05)] {
                let output=RegionalRendering.output(rect,width:w,height:h)
                let support=RegionalRendering.hdrSupport(output:output,width:w,height:h)
                check(support.contains(output),"support contains visible pixels")
                check(full.contains(support),"support clipped to texture")
                check(support==support.integral,"integer texel bounds")
            }
            check(RegionalRendering.output(.null,width:w,height:h)==full,"unknown fails open")
        }
        let strip=RegionalRendering.output(CGRect(x:0,y:0,width:0.05,height:1),width:1280,height:800)
        let support=RegionalRendering.hdrSupport(output:strip,width:1280,height:800)
        check(support.width<1280 && support.width>64,"bloom expands but allows regional shading")
        for column in 0..<4 {
            let region=CGRect(x:Double(column)/4,y:0,width:0.25,height:1)
            let visible=RegionalRendering.output(region,width:1280,height:800)
            let crop=RegionalRendering.tileCrop(region,width:1280,height:800)
            check(crop.contains(visible),"overlap contains visible strip")
            check(crop.width==(column==0 || column==3 ? 321 : 322),"one-texel overlap")
            for pixel in 0..<720 {
                let reference=(Double(column*720+pixel)+0.5)*1280/2880-0.5
                let throughLayer=Double(crop.minX)+Double(visible.minX-crop.minX)+(Double(pixel)+0.5)*Double(visible.width)/720-0.5
                check(abs(reference-throughLayer)<1e-10,"global reconstruction across backing-pixel seams")
            }
        }
        print("PASS: regional bounds, odd/narrow textures, bloom halo and unknown visibility")
    }
}
