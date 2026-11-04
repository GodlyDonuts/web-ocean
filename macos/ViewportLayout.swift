import Foundation

// Keeps pixel and mesh density consistent when a window moves between displays
// or changes aspect ratio. No independent minimum on each axis: that would
// stretch very narrow or very wide viewports.
struct ViewportLayout {
    let width: Int
    let height: Int
    let columns: Int
    let rows: Int

    init(pointWidth: Double, pointHeight: Double, backingScale: Double,
         pixelBudget: Double = 1280*800, textureLimit: Int = 16384) {
        let scale = backingScale.isFinite && backingScale > 0 ? min(backingScale,16) : 1
        let sourceWidth = pointWidth.isFinite && pointWidth > 0 ? pointWidth : 1
        let sourceHeight = pointHeight.isFinite && pointHeight > 0 ? pointHeight : 1
        let nativeWidth = min(Double.greatestFiniteMagnitude.squareRoot(),sourceWidth)*scale
        let nativeHeight = min(Double.greatestFiniteMagnitude.squareRoot(),sourceHeight)*scale
        let limit = Double(max(1,textureLimit))
        let budget = pixelBudget.isFinite && pixelBudget > 0 ? pixelBudget : 1280*800
        let factor = min(1,sqrt(budget/nativeWidth/nativeHeight),limit/nativeWidth,limit/nativeHeight)
        width = max(1,min(textureLimit,Int((nativeWidth*factor).rounded())))
        height = max(1,min(textureLimit,Int((nativeHeight*factor).rounded())))
        // Match or exceed the original projected grid's per-pixel density.
        columns = max(8,((Int(ceil(Double(width)*256/1280))+7)/8)*8)
        rows = max(8,((Int(ceil(Double(height)*192/800))+7)/8)*8)
    }
}
