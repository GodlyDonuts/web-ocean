import Foundation
import Metal

enum Resource {
    case buffer(MTLBuffer), texture(MTLTexture), sampler(MTLSamplerState)
}

// These ranges preserve original shader indices, including nil entries in gaps.
// Arrays and zero offsets are prepared once and passed through Metal’s Swift API.
private struct BindingSlots<Value> {
    let values: [Value?]
    let range: Range<Int>

    init(_ entries: [(Int, Value)]) {
        guard let first = entries.first, let last = entries.last else {
            values = []; range = 0..<0; return
        }
        range = first.0..<(last.0+1)
        var slots = [Value?](repeating: nil, count: range.count)
        for (index,value) in entries { slots[index-range.lowerBound] = value }
        values = slots
    }
}

final class ResourceBindings {
    let resources: [Resource]
    private let buffers: BindingSlots<MTLBuffer>
    private let textures: BindingSlots<MTLTexture>
    private let samplers: BindingSlots<MTLSamplerState>
    private let offsets: [Int]

    init(_ resources: [Resource]) {
        self.resources = resources
        var bufferEntries: [(Int,MTLBuffer)] = []
        var textureEntries: [(Int,MTLTexture)] = []
        var samplerEntries: [(Int,MTLSamplerState)] = []
        for (index,resource) in resources.enumerated() {
            switch resource {
            case .buffer(let buffer): bufferEntries.append((index,buffer))
            case .texture(let texture): textureEntries.append((index,texture))
            case .sampler(let sampler): samplerEntries.append((index,sampler))
            }
        }
        buffers = BindingSlots(bufferEntries)
        textures = BindingSlots(textureEntries)
        samplers = BindingSlots(samplerEntries)
        offsets = [Int](repeating: 0, count: buffers.range.count)
    }

    func bind(to encoder: MTLComputeCommandEncoder) {
        if !buffers.values.isEmpty { encoder.setBuffers(buffers.values, offsets: offsets, range: buffers.range) }
        if !textures.values.isEmpty { encoder.setTextures(textures.values, range: textures.range) }
        if !samplers.values.isEmpty { encoder.setSamplerStates(samplers.values, range: samplers.range) }
    }

    func bind(to encoder: MTLRenderCommandEncoder, vertexSlots: UInt32) {
        if !buffers.values.isEmpty { encoder.setFragmentBuffers(buffers.values, offsets: offsets, range: buffers.range) }
        if !textures.values.isEmpty { encoder.setFragmentTextures(textures.values, range: textures.range) }
        if !samplers.values.isEmpty { encoder.setFragmentSamplerStates(samplers.values, range: samplers.range) }
        // Fullscreen shaders have no vertex resources. Ocean vertices use three
        // separated slots; binding them individually avoids clearing other slots.
        var remaining = vertexSlots
        while remaining != 0 {
            let index = remaining.trailingZeroBitCount
            remaining &= remaining-1
            switch resources[index] {
            case .buffer(let buffer): encoder.setVertexBuffer(buffer, offset: 0, index: index)
            case .texture(let texture): encoder.setVertexTexture(texture, index: index)
            case .sampler(let sampler): encoder.setVertexSamplerState(sampler, index: index)
            }
        }
    }
}
