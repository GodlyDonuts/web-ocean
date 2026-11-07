import Metal

// Packed linear HDR source, prepared offline. No procedural galaxy synthesis,
// image decoding, network request or per-frame upload in the application.
enum GalaxyAtlas {
    static let width=2048, height=1024
    static func make(device: MTLDevice,queue: MTLCommandQueue,enabled: Bool) throws -> MTLTexture {
        let w=enabled ? width : 1,h=enabled ? height : 1
        let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rg11b10Float,width:w,height:h,mipmapped:enabled)
        descriptor.storageMode = .private;descriptor.usage = .shaderRead
        guard let texture=device.makeTexture(descriptor:descriptor) else { throw OceanFailure(message:"Unable to allocate Milky Way radiance.") }
        texture.label="immutable Milky Way HDR radiance"
        let data: Data
        if enabled {
            guard let url=OceanRenderer.resourceBundle.resourceURL?.appendingPathComponent("Assets/Galaxy/milkyway.r11g11b10f") else { throw OceanFailure(message:"Milky Way asset is missing.") }
            data=try Data(contentsOf:url,options:.mappedIfSafe)
        } else { data=Data(repeating:0,count:4) }
        guard data.count==w*h*4,let upload=data.withUnsafeBytes({ device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared) }),let command=queue.makeCommandBuffer(),let blit=command.makeBlitCommandEncoder() else { throw OceanFailure(message:"Milky Way asset has an invalid size or could not be uploaded.") }
        // The 1×1 inactive placeholder uses a padded row for Metal's blit rules.
        if enabled {
            blit.copy(from:upload,sourceOffset:0,sourceBytesPerRow:w*4,sourceBytesPerImage:w*h*4,sourceSize:MTLSize(width:w,height:h,depth:1),to:texture,destinationSlice:0,destinationLevel:0,destinationOrigin:MTLOrigin(x:0,y:0,z:0))
            blit.generateMipmaps(for:texture)
        } else {
            // A 256-byte source row is required for buffer-to-texture copies.
            guard let zero=device.makeBuffer(length:256,options:.storageModeShared) else { throw OceanFailure(message:"Unable to allocate inactive sky placeholder.") }
            memset(zero.contents(),0,256)
            blit.copy(from:zero,sourceOffset:0,sourceBytesPerRow:256,sourceBytesPerImage:256,sourceSize:MTLSize(width:1,height:1,depth:1),to:texture,destinationSlice:0,destinationLevel:0,destinationOrigin:MTLOrigin(x:0,y:0,z:0))
        }
        blit.endEncoding();command.commit();command.waitUntilCompleted()
        if command.status == .error { throw OceanFailure(message:command.error?.localizedDescription ?? "Milky Way upload failed.") }
        return texture
    }
}
