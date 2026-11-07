import AppKit
let directory=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
func drawIcon(_ size:Int)->Data {
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
    let scale=CGFloat(size)/1024
    let transform=NSAffineTransform();transform.scale(by:scale);transform.concat()
    let rect=NSRect(x:42,y:42,width:940,height:940)
    let clip=NSBezierPath(roundedRect:rect,xRadius:204,yRadius:204);clip.addClip()
    NSGradient(starting:NSColor(calibratedRed:0.045,green:0.13,blue:0.24,alpha:1),ending:NSColor(calibratedRed:0.08,green:0.32,blue:0.42,alpha:1))!.draw(in:rect,angle:90)
    NSColor(calibratedRed:1,green:0.87,blue:0.62,alpha:1).setFill();NSBezierPath(ovalIn:NSRect(x:644,y:641,width:142,height:142)).fill()
    func wave(_ y:CGFloat,_ color:NSColor,_ offset:CGFloat) {
        let p=NSBezierPath();p.move(to:NSPoint(x:0,y:y))
        p.curve(to:NSPoint(x:540,y:y+52),controlPoint1:NSPoint(x:190,y:y+170+offset),controlPoint2:NSPoint(x:330,y:y-105))
        p.curve(to:NSPoint(x:1024,y:y+32),controlPoint1:NSPoint(x:750,y:y+195),controlPoint2:NSPoint(x:870,y:y-85+offset))
        p.line(to:NSPoint(x:1024,y:0));p.line(to:.zero);p.close();color.setFill();p.fill()
    }
    wave(430,NSColor(calibratedRed:0.10,green:0.51,blue:0.60,alpha:1),0)
    wave(319,NSColor(calibratedRed:0.06,green:0.34,blue:0.48,alpha:1),30)
    wave(205,NSColor(calibratedRed:0.035,green:0.21,blue:0.34,alpha:1),-20)
    NSGraphicsContext.restoreGraphicsState();return rep.representation(using:.png,properties:[:])!
}
for n in [16,32,128,256,512] {
    try drawIcon(n).write(to:directory.appendingPathComponent("icon_\(n)x\(n).png"))
    try drawIcon(n*2).write(to:directory.appendingPathComponent("icon_\(n)x\(n)@2x.png"))
}
