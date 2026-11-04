import Foundation
import CoreGraphics

// Backing pixels use a display-local top-left origin. AppKit global points use
// bottom-left; Quartz global coordinates are supplied separately by the caller.
struct DisplayTilePlacement: Equatable {
    let column: Int
    let rowFromTop: Int
    let pixels: CGRect
    let appKitPoints: CGRect
    let quartz: CGRect
}

struct DisplayTileLayout {
    enum LayoutError: Error { case invalidExtent, invalidScale, invalidGrid }
    let pixelWidth: Int
    let pixelHeight: Int
    let tiles: [DisplayTilePlacement]

    init(appKitFrame: CGRect, quartzFrame: CGRect, backingScale: CGFloat,
         columns: Int, rows: Int) throws {
        guard columns > 0, rows > 0, columns <= 256, rows <= 256 else { throw LayoutError.invalidGrid }
        guard backingScale.isFinite, backingScale > 0 else { throw LayoutError.invalidScale }
        for frame in [appKitFrame,quartzFrame] {
            guard frame.minX.isFinite,frame.minY.isFinite,frame.maxX.isFinite,frame.maxY.isFinite,frame.width.isFinite,frame.height.isFinite,
                  frame.width > 0,frame.height > 0 else { throw LayoutError.invalidExtent }
        }
        let width = (appKitFrame.width*backingScale).rounded()
        let height = (appKitFrame.height*backingScale).rounded()
        guard width >= 1,height >= 1,width < CGFloat(Int.max),height < CGFloat(Int.max) else { throw LayoutError.invalidExtent }
        pixelWidth = Int(width); pixelHeight = Int(height)
        let sx = quartzFrame.width/appKitFrame.width, sy = quartzFrame.height/appKitFrame.height
        guard sx.isFinite,sy.isFinite,sx > 0,sy > 0 else { throw LayoutError.invalidExtent }
        var result: [DisplayTilePlacement] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let x0 = (CGFloat(column)*width/CGFloat(columns)).rounded()
                let x1 = (CGFloat(column+1)*width/CGFloat(columns)).rounded()
                let y0 = (CGFloat(row)*height/CGFloat(rows)).rounded()
                let y1 = (CGFloat(row+1)*height/CGFloat(rows)).rounded()
                guard x1 > x0,y1 > y0 else { continue }
                let points = CGRect(x:appKitFrame.minX+x0/backingScale,
                                    y:appKitFrame.maxY-y1/backingScale,
                                    width:(x1-x0)/backingScale,height:(y1-y0)/backingScale)
                let cg = CGRect(x:quartzFrame.minX+(points.minX-appKitFrame.minX)*sx,
                                y:quartzFrame.minY+(appKitFrame.maxY-points.maxY)*sy,
                                width:points.width*sx,height:points.height*sy)
                result.append(DisplayTilePlacement(column:column,rowFromTop:row,
                    pixels:CGRect(x:x0,y:y0,width:x1-x0,height:y1-y0),appKitPoints:points,quartz:cg))
            }
        }
        tiles = result
    }
}
