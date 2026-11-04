import Foundation
import Metal

struct OceanFailure: Error { let message: String }
@main enum NightSkyResourcesTests {
    static func unpack(_ bits: UInt32,_ mantissa: Int) -> Float {
        let exponent=bits>>mantissa,fraction=bits&((1<<mantissa)-1)
        return exponent==0 ? Float(fraction)*pow(2,Float(-14-mantissa)) : (1+Float(fraction)/Float(1<<mantissa))*pow(2,Float(Int(exponent)-15))
    }
    static func main() throws {
        guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else { fatalError("Metal unavailable") }
        let galaxy=try GalaxyAtlas.make(device:device,queue:queue,enabled:true)
        precondition(galaxy.width==2048 && galaxy.height==1024 && galaxy.mipmapLevelCount==12 && galaxy.pixelFormat == .rg11b10Float && galaxy.storageMode == .private)
        let url=Bundle.main.resourceURL!.appendingPathComponent("Assets/Galaxy/milkyway.r11g11b10f")
        let raw=try Data(contentsOf:url)
        let source=raw.withUnsafeBytes{Array($0.bindMemory(to:UInt32.self))}
        let shader="""
        #include <metal_stdlib>
        using namespace metal;
        kernel void sampleSky(texture2d<float,access::read> sky [[texture(0)]],device float4* result [[buffer(1)]],uint i [[thread_position_in_grid]]) {
            uint2 points[6]={uint2(0,0),uint2(1024,512),uint2(1559,677),uint2(2047,1023),uint2(100,200),uint2(1999,800)};
            if(i<6) result[i]=sky.read(points[i]);
        }
        """
        let library=try device.makeLibrary(source:shader,options:nil),pipeline=try device.makeComputePipelineState(function:library.makeFunction(name:"sampleSky")!)
        let output=device.makeBuffer(length:6*16,options:.storageModeShared)!,command=queue.makeCommandBuffer()!,encoder=command.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipeline);encoder.setTexture(galaxy,index:0);encoder.setBuffer(output,offset:0,index:1)
        encoder.dispatchThreads(MTLSize(width:6,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:6,height:1,depth:1));encoder.endEncoding();command.commit();command.waitUntilCompleted()
        precondition(command.status == .completed)
        let points=[(0,0),(1024,512),(1559,677),(2047,1023),(100,200),(1999,800)],values=output.contents().assumingMemoryBound(to:SIMD4<Float>.self)
        for (i,p) in points.enumerated() {
            let word=source[p.1*2048+p.0],expected=SIMD3(unpack(word&2047,6),unpack((word>>11)&2047,6),unpack((word>>22)&1023,5))
            for c in 0..<3 { precondition(values[i][c].isFinite && abs(values[i][c]-expected[c])<1e-7,"GPU packed-HDR decode differs") }
        }
        let disabled=try GalaxyAtlas.make(device:device,queue:queue,enabled:false)
        precondition(disabled.width==1 && disabled.height==1 && disabled.mipmapLevelCount==1)
        let low=try StarField.make(device:device,queue:queue,enabled:true)
        let reference=try StarField.make(device:device,queue:queue,enabled:true,atlasSize:2048)
        precondition(low.count==12000 && reference.count==low.count && low.atlas.width==1024 && reference.atlas.width==2048)
        precondition(Data(bytes:low.catalogue.contents(),count:low.count*16)==Data(bytes:reference.catalogue.contents(),count:reference.count*16),"Reflection resolution changed star identity/flux")
        func mean(_ texture: MTLTexture) -> Float {
            var value=Float16(0)
            withUnsafeMutableBytes(of:&value) { texture.getBytes($0.baseAddress!,bytesPerRow:2,from:MTLRegionMake2D(0,0,1,1),mipmapLevel:texture.mipmapLevelCount-1) }
            return Float(value)
        }
        let a=mean(low.atlas),b=mean(reference.atlas),error=abs(a-b)/max(a,b)
        precondition(a.isFinite && a>0 && b.isFinite && error<0.01,"Reflection atlas changed integrated starlight")
        print("PASS: native R11G11B10 decode matches independent bit unpacking; private HDR atlas/mips, inactive placeholder, deterministic 12,000-star catalogue and reflection mip energy verified without windows.")
        print("Reflection-atlas mean relative error: \(error); galaxy allocation: \(galaxy.allocatedSize) bytes; stars low/reference allocations: \(low.atlas.allocatedSize)/\(reference.atlas.allocatedSize) bytes.")
    }
}
