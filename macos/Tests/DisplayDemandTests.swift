import Foundation
import CoreGraphics

@main
struct DisplayDemandTests {
    static func near(_ a: CGFloat,_ b: CGFloat) { precondition(abs(a-b) < 1e-7,"Coordinate mismatch: \(a), \(b)") }
    static func main() throws {
        var layouts = 0, tiles = 0
        let extents = [(3024,1964),(1920,1080),(3440,1440),(5120,1440),(1080,1920),(4031,1901),(1,1),(2,7),(62,16384)]
        for (w,h) in extents {
            for scale in [CGFloat(1),1.25,1.5,2] {
                for (columns,rows) in [(1,1),(4,3)] {
                    let frame = CGRect(x:-2201.5,y:-703.25,width:CGFloat(w)/scale,height:CGFloat(h)/scale)
                    let quartz = CGRect(x:-4012,y:390,width:CGFloat(w)*0.75,height:CGFloat(h)*1.25)
                    let layout = try DisplayTileLayout(appKitFrame:frame,quartzFrame:quartz,
                        backingScale:scale,columns:columns,rows:rows)
                    precondition(layout.pixelWidth==w && layout.pixelHeight==h)
                    precondition(layout.tiles.count==min(w,columns)*min(h,rows))
                    var area:CGFloat = 0
                    for (index,tile) in layout.tiles.enumerated() {
                        let p=tile.pixels
                        precondition(p.minX>=0 && p.minY>=0 && p.maxX<=CGFloat(w) && p.maxY<=CGFloat(h))
                        precondition(p.width>0 && p.height>0)
                        for v in [p.minX,p.minY,p.width,p.height] { precondition(v==v.rounded()) }
                        area += p.width*p.height
                        near((tile.appKitPoints.minX-frame.minX)*scale,p.minX)
                        near((frame.maxY-tile.appKitPoints.maxY)*scale,p.minY)
                        near(tile.quartz.minX,quartz.minX+p.minX/CGFloat(w)*quartz.width)
                        near(tile.quartz.minY,quartz.minY+p.minY/CGFloat(h)*quartz.height)
                        near(tile.quartz.width,p.width/CGFloat(w)*quartz.width)
                        near(tile.quartz.height,p.height/CGFloat(h)*quartz.height)
                        for other in layout.tiles.dropFirst(index+1) {
                            let overlap=p.intersection(other.pixels)
                            precondition(overlap.isNull || overlap.width<=0 || overlap.height<=0)
                        }
                    }
                    near(area,CGFloat(w)*CGFloat(h))
                    layouts+=1;tiles+=layout.tiles.count
                }
            }
        }
        let valid = CGRect(x:0,y:0,width:100,height:100)
        var rejected=0
        for scale in [CGFloat(0),-1,.infinity,.nan] {
            do { _ = try DisplayTileLayout(appKitFrame:valid,quartzFrame:valid,backingScale:scale,columns:4,rows:3);preconditionFailure("Accepted invalid scale") }
            catch { rejected+=1 }
        }
        for (c,r) in [(0,3),(4,0),(-1,3),(257,3)] {
            do { _ = try DisplayTileLayout(appKitFrame:valid,quartzFrame:valid,backingScale:2,columns:c,rows:r);preconditionFailure("Accepted invalid grid") }
            catch { rejected+=1 }
        }
        for frame in [CGRect.zero,CGRect(x:0,y:0,width:CGFloat.infinity,height:1),CGRect(x:CGFloat.nan,y:0,width:1,height:1)] {
            do { _ = try DisplayTileLayout(appKitFrame:frame,quartzFrame:valid,backingScale:2,columns:4,rows:3);preconditionFailure("Accepted invalid extent") }
            catch { rejected+=1 }
        }
        func request(_ id:String,_ visibility:SurfaceVisibility,_ fps:Int,_ bands:UInt8,_ world:String="ocean") -> SurfaceDemandRequest {
            SurfaceDemandRequest(surfaceID:id,worldID:world,visibility:visibility,framesPerSecond:fps,requiredWaveBands:bands)
        }
        let hidden=request("hidden",.occluded,240,0x3f)
        precondition(SharedSurfaceDemand.plan([hidden]).isEmpty)
        let mixed=SharedSurfaceDemand.plan([hidden,request("near",.visible,30,0x07),request("far",.visible,60,0x03)])
        precondition(mixed["ocean"]!.presentationHz==60)
        precondition(mixed["ocean"]!.waveBandHz==[60,60,30,0,0,0])
        let unknown=SharedSurfaceDemand.plan([request("pending",.unknown,0,0)])
        precondition(unknown["ocean"]!.waveBandHz==[Int](repeating:30,count:6))
        let sky=SharedSurfaceDemand.plan([request("sky-with-closed-support",.visible,60,0)])
        precondition(sky["ocean"]!.requiresGPUWork && sky["ocean"]!.waveBandHz==[Int](repeating:0,count:6))
        let separated=SharedSurfaceDemand.plan([request("a",.visible,30,0x3f,"local"),request("b",.visible,60,1,"remote")])
        precondition(separated.count==2 && separated["local"]!.presentationHz==30 && separated["remote"]!.presentationHz==60)
        precondition(SharedSurfaceDemand.plan([request("a",.visible,60,0x3f)],suspended:true).isEmpty)
        let invalid=SharedSurfaceDemand.plan([request("invalid-bands",.visible,30,0x80)])
        precondition(invalid["ocean"]!.waveBandHz==[Int](repeating:30,count:6))
        let duplicate=SharedSurfaceDemand.plan([request("same",.visible,30,1),request("same",.visible,60,2)])
        precondition(duplicate["ocean"]!.surfaceIDs.count==1 && duplicate["ocean"]!.waveBandHz==[30,60,0,0,0,0])
        var suspension=SurfaceSuspensionState()
        suspension.set(.displaySleep,active:true)
        suspension.set(.inactiveSession,active:true)
        suspension.set(.displaySleep,active:false)
        precondition(suspension.isSuspended)
        suspension.set(.systemSleep,active:true)
        suspension.set(.inactiveSession,active:false)
        precondition(suspension.isSuspended)
        suspension.set(.systemSleep,active:false)
        precondition(!suspension.isSuspended)
        print("PASS: \(layouts) layouts / \(tiles) tile placements, \(rejected) invalid inputs, conservative shared-world cadence contracts; no windows or GPU work.")
    }
}
