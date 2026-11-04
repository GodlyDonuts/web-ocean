import Foundation
import Metal

@main struct FFTTableVerification {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { fatalError("Metal unavailable") }
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let tests = root.appendingPathComponent("macos/Tests")
        let shaders = tests.appendingPathComponent("Experiments/FFTTable")
        let options = MTLCompileOptions(); options.languageVersion = .version2_3
        func pipeline(_ url: URL, prefix: String = "") throws -> MTLComputePipelineState {
            let text = prefix + (try String(contentsOf:url,encoding:.utf8))
            let library = try device.makeLibrary(source: text, options: options)
            return try device.makeComputePipelineState(function: library.makeFunction(name:"main_")!)
        }
        let referenceRow = try pipeline(tests.appendingPathComponent("FFT_ROWS_REFERENCE.metal"))
        let referenceCol = try pipeline(tests.appendingPathComponent("FFT_COLS_REFERENCE.metal"))
        let simdRow = try pipeline(shaders.appendingPathComponent("FFT_ROWS.metal"),prefix:"#define FFT_TWIDDLE_TABLE 1\n")
        let simdCol = try pipeline(shaders.appendingPathComponent("FFT_COLS.metal"),prefix:"#define FFT_TWIDDLE_TABLE 1\n#define OCEAN_PACKED_JACOBIAN 0\n")
        let initialization = try pipeline(shaders.appendingPathComponent("TWIDDLE_INIT.metal"))
        let twiddles = device.makeBuffer(length:8*128*8,options:.storageModePrivate)!
        let setup = queue.makeCommandBuffer()!, initEncoder = setup.makeComputeCommandEncoder()!
        initEncoder.setComputePipelineState(initialization); initEncoder.setBuffer(twiddles,offset:0,index:0)
        initEncoder.dispatchThreadgroups(MTLSize(width:1,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:128,height:1,depth:1))
        initEncoder.endEncoding(); setup.commit(); setup.waitUntilCompleted()
        if let error = setup.error { throw error }
        let n = 256, layers = 6, count = n*n*layers*4, bytes = count*4
        let a = device.makeBuffer(length:bytes,options:.storageModeShared)!
        let b = device.makeBuffer(length:bytes,options:.storageModeShared)!
        let sizes = device.makeBuffer(length:128,options:.storageModeShared)!
        memset(sizes.contents(),0,128)
        let ra = device.makeBuffer(length:bytes,options:.storageModeShared)!, rb = device.makeBuffer(length:bytes,options:.storageModeShared)!
        let sa = device.makeBuffer(length:bytes,options:.storageModeShared)!, sb = device.makeBuffer(length:bytes,options:.storageModeShared)!
        func textures() -> [MTLTexture] {
            (0..<3).map { _ in
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba16Float,width:n,height:n,mipmapped:false)
                d.textureType = .type2DArray; d.arrayLength = layers; d.usage = [.shaderRead,.shaderWrite]; d.storageMode = .private
                return device.makeTexture(descriptor:d)!
            }
        }
        let referenceTextures = textures(), simdTextures = textures()
        let readbackBytes = n*n*layers*8
        let referenceReadbacks = (0..<3).map { _ in device.makeBuffer(length:readbackBytes,options:.storageModeShared)! }
        let simdReadbacks = (0..<3).map { _ in device.makeBuffer(length:readbackBytes,options:.storageModeShared)! }
        let groups = MTLSize(width:n,height:1,depth:layers), threads = MTLSize(width:128,height:1,depth:1)
        func row(_ encoder: MTLComputeCommandEncoder, _ state: MTLComputePipelineState, _ oa: MTLBuffer, _ ob: MTLBuffer) {
            encoder.setComputePipelineState(state)
            if state === simdRow { encoder.setBuffer(twiddles,offset:0,index:4) }
            encoder.setBuffer(a,offset:0,index:0); encoder.setBuffer(b,offset:0,index:1)
            encoder.setBuffer(oa,offset:0,index:2); encoder.setBuffer(ob,offset:0,index:3)
            encoder.setBuffer(sizes,offset:0,index:30)
            encoder.dispatchThreadgroups(groups,threadsPerThreadgroup:threads)
            encoder.memoryBarrier(scope:.buffers)
        }
        func col(_ encoder: MTLComputeCommandEncoder, _ state: MTLComputePipelineState, _ ia: MTLBuffer, _ ib: MTLBuffer, _ out: [MTLTexture]) {
            encoder.setComputePipelineState(state)
            if state === simdCol { encoder.setBuffer(twiddles,offset:0,index:5) }
            encoder.setBuffer(ia,offset:0,index:0); encoder.setBuffer(ib,offset:0,index:1)
            encoder.setBuffer(sizes,offset:0,index:30)
            for i in 0..<3 { encoder.setTexture(out[i],index:i+2) }
            encoder.dispatchThreadgroups(groups,threadsPerThreadgroup:threads)
            encoder.memoryBarrier(scope:[.buffers,.textures])
        }
        func execute(_ encode: (MTLCommandBuffer)->Void) throws -> Double {
            let command = queue.makeCommandBuffer()!
            encode(command); command.commit(); command.waitUntilCompleted()
            if let error = command.error { throw error }
            return (command.gpuEndTime-command.gpuStartTime)*1000
        }
        var results: [[String:Any]] = []
        var seed: UInt32 = 0x12345678
        for name in ["zero","impulse","frequency","random"] {
            let pa = a.contents().bindMemory(to:Float.self,capacity:count), pb = b.contents().bindMemory(to:Float.self,capacity:count)
            for i in 0..<count {
                switch name {
                case "zero": pa[i] = 0; pb[i] = 0
                case "impulse": pa[i] = i%1024 < 4 ? 0.001*Float(i%4+1) : 0; pb[i] = -pa[i]*0.5
                case "frequency": pa[i] = i%1024 >= 124 && i%1024 < 128 ? 0.002 : 0; pb[i] = pa[i]*0.7
                default:
                    seed = seed &* 1664525 &+ 1013904223
                    pa[i] = (Float(seed>>8)/16777216-0.5)*0.0005
                    seed = seed &* 1664525 &+ 1013904223
                    pb[i] = (Float(seed>>8)/16777216-0.5)*0.0005
                }
            }
            _ = try execute { command in
                let e = command.makeComputeCommandEncoder()!
                row(e,referenceRow,ra,rb); row(e,simdRow,sa,sb)
                col(e,referenceCol,ra,rb,referenceTextures); col(e,simdCol,sa,sb,simdTextures)
                e.endEncoding()
                let blit = command.makeBlitCommandEncoder()!
                for i in 0..<3 { for layer in 0..<layers {
                    for (t,o) in [(referenceTextures[i],referenceReadbacks[i]),(simdTextures[i],simdReadbacks[i])] {
                        blit.copy(from:t,sourceSlice:layer,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:n,height:n,depth:1),to:o,destinationOffset:layer*n*n*8,destinationBytesPerRow:n*8,destinationBytesPerImage:n*n*8)
                    }
                } }
                blit.endEncoding()
            }
            var rowError:Float = 0, halfError:Float = 0, differentHalfValues = 0, differentRowValues = 0
            for (r,s) in [(ra,sa),(rb,sb)] {
                let pr = r.contents().bindMemory(to:Float.self,capacity:count), ps = s.contents().bindMemory(to:Float.self,capacity:count)
                for i in 0..<count {
                    guard pr[i].isFinite && ps[i].isFinite else { fatalError("Nonfinite row result") }
                    rowError = max(rowError,abs(pr[i]-ps[i]))
                    if pr[i].bitPattern != ps[i].bitPattern { differentRowValues += 1 }
                }
            }
            for i in 0..<3 {
                let pr = referenceReadbacks[i].contents().bindMemory(to:Float16.self,capacity:readbackBytes/2)
                let ps = simdReadbacks[i].contents().bindMemory(to:Float16.self,capacity:readbackBytes/2)
                for j in 0..<readbackBytes/2 {
                    let r = Float(pr[j]), s = Float(ps[j])
                    guard r.isFinite && s.isFinite else { fatalError("Nonfinite assembled result") }
                    halfError = max(halfError,abs(r-s))
                    if pr[j].bitPattern != ps[j].bitPattern { differentHalfValues += 1 }
                }
            }
            // Check independent double-precision DFTs on spatial frequencies and random rows.
            var dftError = 0.0
            let ps = sa.contents().bindMemory(to:Float.self,capacity:count)
            for rowIndex in [0,73,255,512,1535] { for component in [0,2] { for k in [0,1,7,31,64,127,255] {
                var real = 0.0, imag = 0.0
                for j in 0..<n {
                    let angle = 2*Double.pi*Double(j*k)/Double(n), offset = rowIndex*n*4+j*4+component
                    real += Double(pa[offset])*cos(angle)-Double(pa[offset+1])*sin(angle)
                    imag += Double(pa[offset])*sin(angle)+Double(pa[offset+1])*cos(angle)
                }
                let offset = rowIndex*n*4+k*4+component
                dftError = max(dftError,abs(real-Double(ps[offset])),abs(imag-Double(ps[offset+1])))
            } } }
            guard rowError < 0.000001, halfError < 0.01, dftError < 0.000001 else {
                fatalError("FFT mismatch: rows \(rowError), assembled \(halfError), DFT \(dftError)")
            }
            results.append(["case":name,"rowMaxAbsoluteError":Double(rowError),"assembledMaxAbsoluteError":Double(halfError),"differentHalfValues":differentHalfValues,"differentRowValues":differentRowValues,"doubleDFTMaxAbsoluteError":dftError])
        }
        let report: [String:Any] = ["device":device.name,"cases":results]
        let data = try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:root.appendingPathComponent("macos/build/fft-table-report.json"))
        print(String(data:data,encoding:.utf8)!)
    }
}
