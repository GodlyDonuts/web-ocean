import Foundation
import Metal

@main struct CloudDensityBoundVerification {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { fatalError("Metal unavailable") }
        let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let shader = try String(contentsOf:root.appendingPathComponent("macos/Shaders/SKY_BG.metal"),encoding:.utf8)
        let probe = """
        [[max_total_threads_per_threadgroup(128)]] kernel void densityProbe(
            uint id [[thread_position_in_grid]], constant Frame& F [[buffer(0)]], device metal::float4* output [[buffer(1)]]) {
            uint a = pcgHash(id*1664525u+1013904223u), b = pcgHash(a+0x61234578u);
            metal::float2 q = metal::float2(float(a),float(b))*0.0000000698491931-metal::float2(150.0);
            const float footprints[5] = {0.0,0.003,0.02,0.15,0.6};
            float fp = footprints[id%5u];
            int oct = 3+int(id%3u);
            bool saturated = false;
        #if CLOUD_BOUNDED_DENSITY
            float value = boundedLowDensity(q,fp,oct,F,saturated);
        #else
            float value = lowDensity(q,fp,oct,F);
        #endif
            output[id] = metal::float4(value,saturated ? 1.0 : 0.0,fp,float(oct));
        }
        """
        let options = MTLCompileOptions(); options.languageVersion = .version2_3
        var states: [[MTLComputePipelineState]] = []
        for stable in 0...1 {
            var pair: [MTLComputePipelineState] = []
            for bound in 0...1 {
                let source = "#define CLOUD_SKIP_ZERO 1\n#define CLOUD_STABLE_TIME \(stable)\n#define CLOUD_BOUNDED_DENSITY \(bound)\n"+shader+probe
                let library = try device.makeLibrary(source:source,options:options)
                pair.append(try device.makeComputePipelineState(function:library.makeFunction(name:"densityProbe")!))
            }
            states.append(pair)
        }
        let count = 65536, frame = device.makeBuffer(length:608,options:.storageModeShared)!
        let output = (0..<2).map { _ in device.makeBuffer(length:count*16,options:.storageModeShared)! }
        memset(frame.contents(),0,frame.length)
        let floats = frame.contents().bindMemory(to:Float.self,capacity:152)
        var results: [[String:Any]] = [], allPassed = true
        for time in [0.0,45,599.95,600.05,Double(30*86400)] {
            let clock = AnimationClock(start:time)
            floats[95] = clock.detailTime
            clock.writeCloudShifts(to:UnsafeMutableBufferPointer(start:frame.contents().advanced(by:384).assumingMemoryBound(to:UInt32.self),count:56))
            for coverage: Float in [0.05,0.4,1.0] {
                floats[93] = coverage
                let command = queue.makeCommandBuffer()!, encoder = command.makeComputeCommandEncoder()!
                for variant in 0...1 {
                    encoder.setComputePipelineState(states[clock.stableDetails ? 1 : 0][variant])
                    encoder.setBuffer(frame,offset:0,index:0); encoder.setBuffer(output[variant],offset:0,index:1)
                    encoder.dispatchThreadgroups(MTLSize(width:count/128,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:128,height:1,depth:1))
                }
                encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
                if let error = command.error { throw error }
                let a = output[0].contents().bindMemory(to:Float.self,capacity:count*4), b = output[1].contents().bindMemory(to:Float.self,capacity:count*4)
                var changed = 0, changedBits = 0, classified = 0, invalidClassifications = 0
                var maximumError: Float = 0
                for i in 0..<count {
                    let x = a[i*4], y = b[i*4]
                    guard x.isFinite && y.isFinite && x >= 0 && x <= 1 && y >= 0 && y <= 1 else { fatalError("Invalid density") }
                    if x != y { changed += 1; maximumError = max(maximumError,abs(x-y)) }
                    if x.bitPattern != y.bitPattern { changedBits += 1 }
                    if b[i*4+1] == 1 { classified += 1; if x != 1 { invalidClassifications += 1 } }
                }
                let result: [String:Any] = ["time":time,"coverage":coverage,"stable":clock.stableDetails,"comparedValues":count,"changedValues":changed,"changedBits":changedBits,"maximumError":maximumError,"earlySaturated":classified,"invalidClassifications":invalidClassifications]
                results.append(result)
                print(String(data:try JSONSerialization.data(withJSONObject:result,options:.sortedKeys),encoding:.utf8)!)
                allPassed = allPassed && changed == 0 && changedBits == 0 && invalidClassifications == 0
            }
        }
        let result: [String:Any] = ["passed":allPassed,"device":device.name,"cases":results]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("macos/build/cloud-density-bound-verification.json"))
        guard allPassed else { fatalError("Bounded shadow density failed exact comparison") }
        print("PASS: every bounded density and classification matches the reference.")
    }
}
