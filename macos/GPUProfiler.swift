import Metal

// Optional instrumentation. Disabled during ordinary rendering: encoder boundaries
// and counter sampling can perturb timings, so use this to locate work, not to
// claim production frame times.
final class GPUProfiler {
    let samples: MTLCounterSampleBuffer
    private(set) var labels: [String] = []
    private var totals: [String: Double] = [:]
    private var measuredFrames = 0

    init?(device: MTLDevice) {
        guard device.supportsCounterSampling(.atStageBoundary),
              let set = device.counterSets?.first(where: { $0.name == MTLCommonCounterSet.timestamp.rawValue }) else { return nil }
        let descriptor = MTLCounterSampleBufferDescriptor()
        descriptor.counterSet = set
        descriptor.sampleCount = 128
        descriptor.storageMode = .shared
        descriptor.label = "Ocean GPU stage timestamps"
        guard let buffer = try? device.makeCounterSampleBuffer(descriptor: descriptor) else { return nil }
        samples = buffer
    }

    func beginFrame() { labels.removeAll(keepingCapacity: true) }

    private func next(_ name: String) -> Int {
        let index = labels.count*2
        precondition(index+1 < samples.sampleCount, "GPU timestamp capacity exceeded")
        labels.append(name)
        return index
    }

    func compute(_ label: String) -> MTLComputePassDescriptor {
        let d = MTLComputePassDescriptor()
        let a = d.sampleBufferAttachments[0]!
        let index = next(label)
        a.sampleBuffer = samples
        a.startOfEncoderSampleIndex = index
        a.endOfEncoderSampleIndex = index+1
        return d
    }

    func render(_ descriptor: MTLRenderPassDescriptor, label: String) {
        let a = descriptor.sampleBufferAttachments[0]!
        let vertex = next(label + " vertices")
        let fragment = next(label)
        a.sampleBuffer = samples
        a.startOfVertexSampleIndex = vertex
        a.endOfVertexSampleIndex = vertex+1
        a.startOfFragmentSampleIndex = fragment
        a.endOfFragmentSampleIndex = fragment+1
    }

    // Called after GPU completion and before releasing the frame semaphore.
    func resolve(labels: [String]) -> [String: Double] {
        guard !labels.isEmpty, let data = try? samples.resolveCounterRange(0..<labels.count*2) else { return [:] }
        return data.withUnsafeBytes { raw in
            let timestamps = raw.bindMemory(to: UInt64.self)
            var stages: [String: Double] = [:]
            for (i,label) in labels.enumerated() {
                let start = timestamps[i*2], end = timestamps[i*2+1]
                if start > 0 && end >= start && end != UInt64.max {
                    stages[label,default:0] += Double(end-start)/1_000_000
                }
            }
            return stages
        }
    }

    func record(_ stages: [String: Double], frame: Int) {
        guard frame > 60, !stages.isEmpty else { return } // Ignore compilation/initialization/warmup.
        measuredFrames += 1
        for (name,ms) in stages { totals[name,default:0] += ms }
    }

    var averageMilliseconds: [String: Double] {
        guard measuredFrames > 0 else { return [:] }
        return totals.mapValues { $0/Double(measuredFrames) }
    }
}
