import Foundation
import Metal

@main struct FFTLayoutVerification {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { fatalError("Metal unavailable") }
        let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let folder = root.appendingPathComponent("macos/Tests/Experiments/FFTLayout")
        let options = MTLCompileOptions(); options.languageVersion = .version2_3
        func pipeline(_ name: String, layout: Int) throws -> MTLComputePipelineState {
            let source = "#define FFT_LAYOUT \(layout)\n#define OCEAN_PACKED_JACOBIAN 1\n"+(try String(contentsOf:folder.appendingPathComponent(name+".metal"),encoding:.utf8))
            let library = try device.makeLibrary(source:source,options:options)
            return try device.makeComputePipelineState(function:library.makeFunction(name:"main_")!)
        }
        var rows: [MTLComputePipelineState] = [], columns: [MTLComputePipelineState] = []
        for layout in 0...5 { rows.append(try pipeline("SIM_EVOLVE_ROWS",layout:layout)); columns.append(try pipeline("FFT_COLS",layout:layout)) }
        let n = 256, layers = 6, floats = n*n*layers*4, bytes = floats*4
        func buffer(_ length: Int, _ shared: Bool = true) -> MTLBuffer { device.makeBuffer(length:length,options:shared ? .storageModeShared : .storageModePrivate)! }
        let sim = buffer(224), sizes = buffer(128), h0 = buffer(bytes), a = buffer(bytes,false), b = buffer(bytes,false)
        let readA = buffer(bytes), readB = buffer(bytes), halfBytes = n*n*layers*8
        let textureReadbacks = (0..<3).map { _ in buffer(halfBytes) }
        let textures = (0..<3).map { _ -> MTLTexture in
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:n,height:n,mipmapped:false)
            d.textureType = .type2DArray; d.arrayLength = layers; d.storageMode = .private; d.usage = [.shaderRead,.shaderWrite]
            return device.makeTexture(descriptor:d)!
        }
        memset(sim.contents(),0,sim.length); memset(sizes.contents(),0,sizes.length)
        let params = sim.contents().bindMemory(to:Float.self,capacity:56)
        for (i,length) in [Float(1103),211.3,39.7,7.43,1.393,0.2617].enumerated() { params[i] = length }
        params[48] = 1.25; params[50] = 600; params[52] = 45
        let input = h0.contents().bindMemory(to:Float.self,capacity:floats)
        var seed: UInt32 = 0x61234578
        for i in 0..<floats { seed = seed &* 1664525 &+ 1013904223; input[i] = (Float(seed>>8)/16777216-0.5)*0.0005 }
        func encode(_ layout: Int, encoder: MTLComputeCommandEncoder) {
            encoder.setComputePipelineState(rows[layout])
            for (i,v) in [sim,h0,a,b].enumerated() { encoder.setBuffer(v,offset:0,index:i) }
            encoder.setBuffer(sizes,offset:0,index:30)
            encoder.dispatchThreadgroups(MTLSize(width:n,height:1,depth:layers),threadsPerThreadgroup:MTLSize(width:128,height:1,depth:1))
            encoder.setComputePipelineState(columns[layout])
            encoder.setBuffer(a,offset:0,index:0); encoder.setBuffer(b,offset:0,index:1)
            for (i,t) in textures.enumerated() { encoder.setTexture(t,index:i+2) }
            encoder.dispatchThreadgroups(MTLSize(width:n,height:1,depth:layers),threadsPerThreadgroup:MTLSize(width:128,height:1,depth:1))
        }
        func execute(_ layout: Int, iterations: Int, readback: Bool = false) throws -> Double {
            let command = queue.makeCommandBuffer()!, encoder = command.makeComputeCommandEncoder()!
            for _ in 0..<iterations { encode(layout,encoder:encoder) }
            encoder.endEncoding()
            if readback {
                let blit = command.makeBlitCommandEncoder()!
                blit.copy(from:a,sourceOffset:0,to:readA,destinationOffset:0,size:bytes)
                blit.copy(from:b,sourceOffset:0,to:readB,destinationOffset:0,size:bytes)
                for (i,t) in textures.enumerated() { for layer in 0..<layers {
                    blit.copy(from:t,sourceSlice:layer,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:n,height:n,depth:1),to:textureReadbacks[i],destinationOffset:layer*n*n*8,destinationBytesPerRow:n*8,destinationBytesPerImage:n*n*8)
                } }
                blit.endEncoding()
            }
            command.commit(); command.waitUntilCompleted()
            if let error = command.error { throw error }
            return (command.gpuEndTime-command.gpuStartTime)*1000/Double(iterations)
        }
        _ = try execute(0,iterations:2,readback:true)
        let baselineRows = [readA,readB].map { Data(bytes:$0.contents(),count:bytes) }
        let baselineTextures = textureReadbacks.map { Data(bytes:$0.contents(),count:halfBytes) }
        var quality: [[String:Any]] = []
        for layout in 0...5 {
            _ = try execute(layout,iterations:1,readback:true)
            var changed = 0
            for (k,r) in [readA,readB].enumerated() {
                baselineRows[k].withUnsafeBytes { raw in
                    let expected = raw.bindMemory(to:UInt32.self), actual = r.contents().bindMemory(to:UInt32.self,capacity:floats)
                    for layer in 0..<layers { for y in 0..<n { for x in 0..<n {
                        let physical: Int
                        if layout == 1 { physical = (layer*n+x)*n+y }
                        else if layout >= 2 {
                            let tile = 1<<layout
                            physical = layer*n*n+((y/tile)*(n/tile)+x/tile)*tile*tile+(y%tile)*tile+x%tile
                        } else { physical = (layer*n+y)*n+x }
                        let logical = (layer*n+y)*n+x
                        for component in 0..<4 { if expected[logical*4+component] != actual[physical*4+component] { changed += 1 } }
                    } } }
                }
            }
            var changedTextureBytes = 0
            for (i,r) in textureReadbacks.enumerated() { changedTextureBytes += zip(baselineTextures[i],Data(bytes:r.contents(),count:halfBytes)).filter{$0 != $1}.count }
            guard changed == 0 && changedTextureBytes == 0 else { fatalError("Layout \(layout) changed rows or assembled half-float textures") }
            quality.append(["layout":layout,"comparedFloat32Values":floats*2,"changedRowBits":changed,"comparedHalfTextureBytes":halfBytes*3,"changedHalfTextureBytes":changedTextureBytes])
        }
        var timings = (0...5).map { _ in [Double]() }
        for layout in 0...5 { _ = try execute(layout,iterations:3) }
        for round in 0..<6 {
            let order = round%2 == 0 ? Array(0...5) : Array((0...5).reversed())
            for layout in order { timings[layout].append(try execute(layout,iterations:12)) }
        }
        var summary: [[String:Any]] = []
        for layout in 0...5 {
            let values = timings[layout].sorted()
            summary.append(["layout":layout,"meanPairMs":values.reduce(0,+)/Double(values.count),"medianPairMs":(values[2]+values[3])/2,"runs":timings[layout]])
        }
        let report: [String:Any] = ["device":device.name,"quality":quality,"timings":summary,"iterationsPerCommand":12,"rounds":6,"note":"Compute-only batch benchmark; full-frame confirmation is required before adoption."]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("macos/build/fft-layout-microbenchmark.json"))
        for result in summary { print(String(data:try JSONSerialization.data(withJSONObject:result,options:.sortedKeys),encoding:.utf8)!) }
        print("PASS: all six layouts preserve normalized row bits and raw assembled texture bytes.")
    }
}
