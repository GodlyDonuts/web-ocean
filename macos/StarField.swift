import Metal

// Deterministic procedural catalogue, rasterized once into a small HDR atlas.
// Filtered mip levels preserve unresolved starlight in the reflection cube.
enum StarField {
    struct Resources { let atlas: MTLTexture; let catalogue: MTLBuffer; let count: Int }
    static func make(device: MTLDevice, queue: MTLCommandQueue, enabled: Bool, atlasSize: Int = 1024) throws -> Resources {
        let width=enabled ? atlasSize : 1,height=enabled ? atlasSize/2 : 1
        var catalogue=[SIMD4<Float>]()
        var pixels=[Float16](repeating:0,count:width*height)
        if enabled {
            var seed: UInt64=0x629ab47d12ee3901
            func random() -> Double {
                seed=seed &* 6364136223846793005 &+ 1442695040888963407
                return Double((seed>>32)&0xffffff)/16777216
            }
            for i in 0..<12000 {
                let longitude=random()*2*Double.pi,latitude=asin(random()*2-1)
                let x=longitude/(2*Double.pi)*Double(width)-0.5,y=(latitude/Double.pi+0.5)*Double(height)-0.5
                let ix=Int(floor(x)),iy=Int(floor(y)),fx=x-floor(x),fy=y-floor(y)
                let magnitude=random()
                let rawEnergy=i<32 ? 0.8+pow(random(),2)*6.5 : exp2(-3.2-pow(magnitude,0.4)*7.5)
                catalogue.append(SIMD4(Float(cos(latitude)*cos(longitude)),Float(cos(latitude)*sin(longitude)),Float(sin(latitude)),Float(rawEnergy)))
                let energy=rawEnergy*(Double(width*height)/2097152)/max(0.05,cos(latitude))
                for dy in 0...1 { for dx in 0...1 {
                    let px=(ix+dx+width)%width,py=max(0,min(height-1,iy+dy))
                    let weight=(dx==0 ? 1-fx : fx)*(dy==0 ? 1-fy : fy)
                    let index=py*width+px
                    pixels[index]=Float16(min(60000,Float(pixels[index])+Float(energy*weight)))
                } }
            }
        }
        let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.r16Float,width:width,height:height,mipmapped:enabled)
        descriptor.storageMode = .shared;descriptor.usage = .shaderRead
        guard let texture=device.makeTexture(descriptor:descriptor) else { throw OceanFailure(message:"Unable to allocate star atlas.") }
        texture.label="immutable HDR stellar catalogue"
        pixels.withUnsafeBytes { texture.replace(region:MTLRegionMake2D(0,0,width,height),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:width*2) }
        if enabled {
            guard let command=queue.makeCommandBuffer(),let blit=command.makeBlitCommandEncoder() else { throw OceanFailure(message:"Unable to filter star atlas.") }
            blit.generateMipmaps(for:texture);blit.endEncoding();command.commit();command.waitUntilCompleted()
            if command.status == .error { throw OceanFailure(message:command.error?.localizedDescription ?? "Star atlas filtering failed.") }
        }
        let count=catalogue.count
        if catalogue.isEmpty { catalogue.append(SIMD4(repeating:0)) }
        guard let buffer=catalogue.withUnsafeBytes({ device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared) }) else { throw OceanFailure(message:"Unable to allocate stellar catalogue.") }
        buffer.label="immutable stellar directions / flux"
        return Resources(atlas:texture,catalogue:buffer,count:count)
    }
}
