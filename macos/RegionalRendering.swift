import Foundation
import CoreGraphics

// Pixel rectangles have a top-left origin. Keep a conservative bounding box:
// one mesh draw, no duplicated geometry or independent simulations per tile.
enum RegionalRendering {
    static let full = CGRect(x:0,y:0,width:1,height:1)

    static func output(_ normalized: CGRect, width: Int, height: Int) -> CGRect {
        guard !normalized.isNull, !normalized.isEmpty,
              [normalized.minX,normalized.minY,normalized.maxX,normalized.maxY].allSatisfy({ $0.isFinite }) else {
            return CGRect(x:0,y:0,width:width,height:height)
        }
        let box=CGRect(x:normalized.minX*CGFloat(width),y:normalized.minY*CGFloat(height),
                       width:normalized.width*CGFloat(width),height:normalized.height*CGFloat(height)).integral
        let clipped=box.intersection(CGRect(x:0,y:0,width:width,height:height))
        return clipped.isEmpty ? CGRect(x:0,y:0,width:width,height:height) : clipped
    }

    // One source texel of overlap prevents independent window scaling from
    // clamping at strip boundaries and exposing vertical interpolation seams.
    static func tileCrop(_ normalized: CGRect,width: Int,height: Int) -> CGRect {
        output(normalized,width:width,height:height).insetBy(dx:-1,dy:0)
            .intersection(CGRect(x:0,y:0,width:width,height:height))
    }

    // Backward support of the actual six-level 13-tap down / 9-tap up bloom.
    // Include bilinear neighbours and a one-texel numerical guard at each edge.
    // All bloom passes remain full resolution; only expensive scene shading is cropped.
    static func hdrSupport(output: CGRect, width: Int, height: Int, levels: Int = 6) -> CGRect {
        let sizes=(0...levels).map { CGSize(width:max(1,width >> $0),height:max(1,height >> $0)) }
        func sample(_ rect: CGRect, from: CGSize, to: CGSize, radius: CGFloat) -> CGRect {
            func axis(_ lo: CGFloat,_ hi: CGFloat,_ a: CGFloat,_ b: CGFloat) -> (CGFloat,CGFloat) {
                let first=floor((lo+0.5)*b/a-0.5-radius)-1
                let last=floor((hi-0.5)*b/a-0.5+radius)+3
                return (max(0,first),min(b,last))
            }
            let x=axis(rect.minX,rect.maxX,from.width,to.width), y=axis(rect.minY,rect.maxY,from.height,to.height)
            return CGRect(x:x.0,y:y.0,width:x.1-x.0,height:y.1-y.0)
        }
        guard levels>0 else { return output }
        var demand=[CGRect](repeating:.null,count:levels)
        demand[0]=sample(output,from:sizes[0],to:sizes[1],radius:0)
        if levels>1 {
            for i in 1..<levels { demand[i]=sample(demand[i-1],from:sizes[i],to:sizes[i+1],radius:1) }
            for i in stride(from:levels-1,through:1,by:-1) {
                demand[i-1]=demand[i-1].union(sample(demand[i],from:sizes[i+1],to:sizes[i],radius:2))
            }
        }
        return output.union(sample(demand[0],from:sizes[1],to:sizes[0],radius:2))
    }
}
