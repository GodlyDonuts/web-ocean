import Foundation
import Metal

// Compare float32 rows before the column FFT and half-float texture stores.
// Synthetic spectra exercise signs, zeros, broad frequencies and large values.
@main struct EvolutionFFTVerification {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { fatalError("Metal unavailable") }
        let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let sources = root.appendingPathComponent("macos/Shaders")
        let options = MTLCompileOptions(); options.languageVersion = .version2_3
        func pipeline(_ name: String) throws -> MTLComputePipelineState {
            let source = try String(contentsOf:sources.appendingPathComponent(name+".metal"),encoding:.utf8)
            let library = try device.makeLibrary(source:source,options:options)
            return try device.makeComputePipelineState(function:library.makeFunction(name:"main_")!)
        }
        let evolve = try pipeline("SIM_EVOLVE"), rows = try pipeline("FFT_ROWS"), fused = try pipeline("SIM_EVOLVE_ROWS")
        let n = 256, layers = 6, count = n*n*layers*4, bytes = count*4
        func buffer(_ bytes: Int) -> MTLBuffer { device.makeBuffer(length:bytes,options:.storageModeShared)! }
        let sim = buffer(224), sizes = buffer(128), h0 = buffer(bytes)
        let specA = buffer(bytes), specB = buffer(bytes), rowA = buffer(bytes), rowB = buffer(bytes), fusedA = buffer(bytes), fusedB = buffer(bytes)
        memset(sim.contents(),0,sim.length); memset(sizes.contents(),0,sizes.length)
        let parameters = sim.contents().bindMemory(to:Float.self,capacity:56)
        for (index,length) in [Float(1103),211.3,39.7,7.43,1.393,0.2617].enumerated() { parameters[index] = length }
        parameters[48] = 1.25; parameters[50] = 600
        var seed: UInt32 = 0x81726354
        var results: [[String:Any]] = []
        for pattern in ["zero","impulse","random","large"] {
            let values = h0.contents().bindMemory(to:Float.self,capacity:count)
            for index in 0..<count {
                switch pattern {
                case "zero": values[index] = 0
                case "impulse": values[index] = index%1024 >= 124 && index%1024 < 128 ? Float(index%4+1)*0.001 : 0
                default:
                    seed = seed &* 1664525 &+ 1013904223
                    values[index] = (Float(seed>>8)/16777216-0.5)*(pattern == "large" ? 20 : 0.0005)
                }
            }
            for phase: Float in [0,45,120,599.95] {
                parameters[52] = phase
                let command = queue.makeCommandBuffer()!, encoder = command.makeComputeCommandEncoder()!
                func dispatch(_ state: MTLComputePipelineState, _ resources: [MTLBuffer], _ groups: MTLSize, _ threads: MTLSize) {
                    encoder.setComputePipelineState(state)
                    for (index,resource) in resources.enumerated() { encoder.setBuffer(resource,offset:0,index:index) }
                    encoder.setBuffer(sizes,offset:0,index:30)
                    encoder.dispatchThreadgroups(groups,threadsPerThreadgroup:threads)
                }
                dispatch(evolve,[sim,h0,specA,specB],MTLSize(width:16,height:16,depth:layers),MTLSize(width:16,height:16,depth:1))
                dispatch(rows,[specA,specB,rowA,rowB],MTLSize(width:n,height:1,depth:layers),MTLSize(width:128,height:1,depth:1))
                dispatch(fused,[sim,h0,fusedA,fusedB],MTLSize(width:n,height:1,depth:layers),MTLSize(width:128,height:1,depth:1))
                encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
                if let error = command.error { throw error }
                var changed = 0, changedBits = 0
                var maximumError: Float = 0
                for (reference,candidate) in [(rowA,fusedA),(rowB,fusedB)] {
                    let a = reference.contents().bindMemory(to:Float.self,capacity:count)
                    let b = candidate.contents().bindMemory(to:Float.self,capacity:count)
                    for index in 0..<count {
                        guard a[index].isFinite && b[index].isFinite else { fatalError("Nonfinite row output") }
                        if a[index] != b[index] { changed += 1; maximumError = max(maximumError,abs(a[index]-b[index])) }
                        if a[index].bitPattern != b[index].bitPattern { changedBits += 1 }
                    }
                }
                let result: [String:Any] = ["pattern":pattern,"time":phase,"comparedFloat32Values":count*2,"changedValues":changed,"changedBitPatterns":changedBits,"maximumError":maximumError]
                results.append(result)
                print(String(data:try JSONSerialization.data(withJSONObject:result,options:.sortedKeys),encoding:.utf8)!)
                guard changed == 0 && changedBits == 0 else { fatalError("Fused evolution changed float32 FFT rows") }
            }
        }
        let report: [String:Any] = ["passed":true,"device":device.name,"cases":results]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("macos/build/evolution-fft-verification.json"))
        print("PASS: fused evolution matches every reference float32 row bit across sixteen input/phase cases.")
    }
}
