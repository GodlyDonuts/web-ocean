import Metal

// One immutable 64³ texture (1 MiB). Periodic value/cellular fields are built
// once on the CPU; the ray marcher uses hardware trilinear filtering.
enum CloudNoise {
    static let size = 64
    private static func hash(_ x: Int, _ y: Int, _ z: Int, _ period: Int, _ seed: UInt32) -> Float {
        var h = UInt32(x & (period-1)) &* 73856093 ^ UInt32(y & (period-1)) &* 19349663 ^ UInt32(z & (period-1)) &* 83492791 ^ seed
        h ^= h >> 16; h &*= 2246822519; h ^= h >> 13; h &*= 3266489917; h ^= h >> 16
        return Float(h & 0xffffff)/16777215
    }
    private static func value(_ p: SIMD3<Float>, period: Int) -> Float {
        let ix = Int(floor(p.x)), iy = Int(floor(p.y)), iz = Int(floor(p.z))
        var f = p-SIMD3(Float(ix),Float(iy),Float(iz)); f = f*f*(SIMD3(repeating:3)-2*f)
        var result: Float = 0
        for z in 0...1 { for y in 0...1 { for x in 0...1 {
            result += hash(ix+x,iy+y,iz+z,period,17) * (x==0 ? 1-f.x : f.x) * (y==0 ? 1-f.y : f.y) * (z==0 ? 1-f.z : f.z)
        } } }
        return result
    }
    private static func cellular(_ p: SIMD3<Float>, period: Int) -> Float {
        let ix = Int(floor(p.x)), iy = Int(floor(p.y)), iz = Int(floor(p.z))
        var nearest: Float = 4
        for z in -1...1 { for y in -1...1 { for x in -1...1 {
            let a=ix+x, b=iy+y, c=iz+z
            let point = SIMD3(Float(a)+hash(a,b,c,period,71),Float(b)+hash(a,b,c,period,137),Float(c)+hash(a,b,c,period,293))
            let d = p-point; nearest = min(nearest,d.x*d.x+d.y*d.y+d.z*d.z)
        } } }
        return max(0,1-sqrt(nearest)*0.85)
    }
    static func make(device: MTLDevice) throws -> MTLTexture {
        let n=size
        var bytes=[UInt8](repeating:0,count:n*n*n*4)
        for z in 0..<n { for y in 0..<n { for x in 0..<n {
            let p=(SIMD3(Float(x),Float(y),Float(z))+0.5)/Float(n)
            let v=value(p*8,period:8), w=cellular(p*8,period:8), detail=cellular(p*16,period:16)
            let i=((z*n+y)*n+x)*4
            bytes[i]=UInt8(max(0,min(255,(v*255).rounded())))
            bytes[i+1]=UInt8(max(0,min(255,(w*255).rounded())))
            bytes[i+2]=UInt8(max(0,min(255,(detail*255).rounded())))
            bytes[i+3]=255
        } } }
        let d=MTLTextureDescriptor()
        d.textureType = .type3D; d.width=n; d.height=n; d.depth=n
        d.pixelFormat = .rgba8Unorm; d.storageMode = .shared; d.usage = .shaderRead
        guard let texture=device.makeTexture(descriptor:d) else { throw OceanFailure(message:"Unable to allocate cloud noise.") }
        texture.label="periodic volumetric cloud shape / erosion"
        bytes.withUnsafeBytes { texture.replace(region:MTLRegionMake3D(0,0,0,n,n,n),mipmapLevel:0,slice:0,withBytes:$0.baseAddress!,bytesPerRow:n*4,bytesPerImage:n*n*4) }
        return texture
    }
}
