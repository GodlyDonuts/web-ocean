import Metal

// Texture writes default to the GPU's native rounding strategy. Probe it once,
// rather than assuming all current and future Apple GPUs round like this M1.
enum MipmapRounding: String {
    case nearestEven, towardZero, unsupported

    static func detect(device: MTLDevice, queue: MTLCommandQueue) throws -> Self {
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void probe(uint2 p [[thread_position_in_grid]],
                          texture2d<float,access::write> output [[texture(0)]],
                          device ushort4* nearest [[buffer(0)]],
                          device ushort4* zero [[buffer(1)]]) {
            uint index = p.y*256+p.x;
            ushort bits = ushort(index & 0x7fff);
            if (bits >= 0x7bff) bits = 0x7bfe;
            float low = float(as_type<half>(bits));
            float high = float(as_type<half>(ushort(bits+1)));
            float4 value = low+(high-low)*float4(0.0f,0.25f,0.5f,0.75f);
            if (index & 0x8000) value = -value;
            half4 h = half4(value);
            ushort4 correction = select(ushort4(0),ushort4(1),abs(float4(h)) > abs(value));
            nearest[index] = as_type<ushort4>(h);
            zero[index] = as_type<ushort4>(h)-correction;
            output.write(value,p);
        }
        """
        let options = MTLCompileOptions()
        options.languageVersion = .version2_3
        let library = try device.makeLibrary(source:source,options:options)
        guard let function = library.makeFunction(name:"probe") else { return .unsupported }
        let pipeline = try device.makeComputePipelineState(function:function)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:256,height:256,mipmapped:false)
        descriptor.usage = [.shaderWrite]
        descriptor.storageMode = .private
        let length = 256*256*8
        guard let texture = device.makeTexture(descriptor:descriptor),
              let nearest = device.makeBuffer(length:length,options:.storageModeShared),
              let zero = device.makeBuffer(length:length,options:.storageModeShared),
              let actual = device.makeBuffer(length:length,options:.storageModeShared),
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else { return .unsupported }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture,index:0)
        encoder.setBuffer(nearest,offset:0,index:0)
        encoder.setBuffer(zero,offset:0,index:1)
        encoder.dispatchThreadgroups(MTLSize(width:32,height:32,depth:1),threadsPerThreadgroup:MTLSize(width:8,height:8,depth:1))
        encoder.endEncoding()
        guard let blit = command.makeBlitCommandEncoder() else { return .unsupported }
        blit.copy(from:texture,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:256,height:256,depth:1),to:actual,destinationOffset:0,destinationBytesPerRow:256*8,destinationBytesPerImage:length)
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return .unsupported }
        let observed = UnsafeRawBufferPointer(start:actual.contents(),count:length)
        if observed.elementsEqual(UnsafeRawBufferPointer(start:zero.contents(),count:length)) { return .towardZero }
        if observed.elementsEqual(UnsafeRawBufferPointer(start:nearest.contents(),count:length)) { return .nearestEven }
        return .unsupported
    }
}
