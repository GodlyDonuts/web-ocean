import AppKit
import Darwin
import MetalKit
import simd

private struct ResourcePlans {
    var evolveRows: ResourceBindings? = nil
    var evolve: ResourceBindings? = nil
    var fftRows: ResourceBindings? = nil
    var fftCols: ResourceBindings? = nil
    var bounds: ResourceBindings? = nil
    var boundsFinal: ResourceBindings? = nil
    var foamUpdate: [ResourceBindings] = []
    var skyLUT: ResourceBindings? = nil
    var sun: ResourceBindings? = nil
    var environment: ResourceBindings? = nil
    var environmentMips: [ResourceBindings] = []
    var lighting: ResourceBindings? = nil
    var visibleSky: ResourceBindings? = nil
    var ocean: [ResourceBindings] = []
    var sky: ResourceBindings? = nil
    var bloomDown: [ResourceBindings] = []
    var bloomUp: [ResourceBindings] = []
    var composite: ResourceBindings? = nil
}

private struct Pipeline {
    let state: MTLComputePipelineState
    let threads: MTLSize
}

struct OceanFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// Native Metal orchestration. Shader binding numbers are explicit in Shaders/*.metal.
final class OceanRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let gate = DispatchSemaphore(value: 1)
    private var compute: [String: Pipeline] = [:]
    private var libraries: [String: MTLLibrary] = [:]
    private var oceanStablePipeline: MTLRenderPipelineState!
    private var oceanStableGuardPipeline: MTLRenderPipelineState!
    private var stableCachePipeline: MTLRenderPipelineState!
    private var prunedCachePipeline: MTLRenderPipelineState?
    private var prunedStableCachePipeline: MTLRenderPipelineState?
    private var specializedSkyAAMask = 3
    private var lastSkyAAMask = 3
    private var oceanGuardPipeline: MTLRenderPipelineState!
    private var oceanPipeline: MTLRenderPipelineState!
    private var skyPipeline: MTLRenderPipelineState!
    private var cachePipeline: MTLRenderPipelineState!
    private var downPipeline: MTLRenderPipelineState!
    private var upPipeline: MTLRenderPipelineState!
    private var compositePipeline: MTLRenderPipelineState!
    private var oceanDepth: MTLDepthStencilState!
    private var skyDepth: MTLDepthStencilState!
    private var clampSampler: MTLSamplerState!
    private var repeatSampler: MTLSamplerState!
    private var simSampler: MTLSamplerState!
    private var linearSampler: MTLSamplerState!
    private var frameBuffer: MTLBuffer!
    private var simBuffer: MTLBuffer!
    private var foamBuffer: MTLBuffer!
    private var atmoBuffer: MTLBuffer!
    private var compositeBuffer: MTLBuffer!
    private var sizesBuffer: MTLBuffer!
    private var verifiedResizeLayouts: [[Int]] = []
    private var verifiedGuardBounds = false
    private var displacementBounds: MTLBuffer!
    private var partialBounds: MTLBuffer!
    private var sunBuffer: MTLBuffer!
    private var lightingTexture: MTLTexture!
    private var skipCloudOctaves = true
    private var packedJacobian = true
    private var useSharedLighting = false
    private var fusedEvolution = true
    private var fusedMipmaps = false
    private var mipmapRounding = MipmapRounding.unsupported
    private var batchBindings = true
    private var resourcePlans = ResourcePlans()
    private var waveBindings: [ResourceBindings] = []
    private var foamBindings: [[ResourceBindings]] = []
    private var waveMipResources: [[Resource]] = []
    private var foamMipResources: [[[Resource]]] = []
    private var h0: MTLBuffer!
    private var specA: MTLBuffer!
    private var specB: MTLBuffer!
    private var tmpA: MTLBuffer!
    private var tmpB: MTLBuffer!
    private var disp: MTLTexture!
    private var deriv: MTLTexture!
    private var moments: MTLTexture!
    private var foamDetail: MTLTexture!
    private var foam: [MTLTexture] = []
    private var trans: MTLTexture!
    private var multipleScatter: MTLTexture!
    private var skyLUT: MTLTexture!
    private var environment: MTLTexture!
    private var hdr: MTLTexture!
    private var msaa: MTLTexture!
    private var depth: MTLTexture!
    private var cachedSky: MTLTexture!
    private var bloom: [MTLTexture] = []
    private var bloomUniforms: [MTLBuffer] = []
    private var mipViews: [String: [MTLTexture]] = [:]
    private var indexBuffer: MTLBuffer!
    private var indexType: MTLIndexType = .uint32
    private var columns = 256, rows = 192
    private let cascadeLengths: [Float] = [1103, 211.3, 39.7, 7.43, 1.393, 0.2617]
    private let n = 256, cascades = 6, foamSize = 512, bloomLevels = 6
    private var width = 0, height = 0
    private var initialized = false, foamFirst = true
    private var foamIndex = 0, envFace = 0
    private var frameIndex = 0
    private var clock = AnimationClock()
    private var time: Float = 0
    private var lastTime: CFTimeInterval = 0
    private var lastSky: CFTimeInterval = -.infinity
    private var lastEnvironment: CFTimeInterval = -.infinity
    private var cachedSkyElapsed = 0.0
    private var lastCache: CFTimeInterval = -.infinity
    private var cacheDirty = true
    private(set) var gpuMilliseconds = 0.0
    private(set) var frames = 0
    private(set) var errors: [String] = []
    private var benchmarkTimes: [Double] = []
    private var benchmarkCPUTimes: [Double] = []
    private var benchmarkThreadCPUTimes: [Double] = []
    private var uniformsDirty = true
    private var fixedStep: Float?
    private var cacheUniforms = true
    private let verificationEnabled = CommandLine.arguments.contains("--verify")
    private let benchmarkEnabled = CommandLine.arguments.contains("--benchmark")
    private var diagnosticFrames = 0
    private var diagnosticTime = CACurrentMediaTime()
    private struct Readback {
        let name: String
        let buffer: MTLBuffer
        let width: Int, height: Int, layers: Int, rowBytes: Int, bytesPerPixel: Int
    }
    private var profiler: GPUProfiler?
    private let diagnostics: Bool
    private var options: [String: String] = [:]
    var isPaused = false {
        didSet { if isPaused != oldValue { lastTime = 0 } }
    }
    var triangleCount: Int { columns * rows * 2 }

    init(view: MTKView, diagnostics: Bool, options: [String: String]) throws {
        guard let device = view.device, let queue = device.makeCommandQueue() else {
            throw OceanFailure(message: "This Mac could not create a Metal device and command queue.")
        }
        guard device.supportsFamily(.apple1) else {
            throw OceanFailure(message: "This renderer requires an Apple silicon Mac for tile-memory render targets.")
        }
        self.device = device
        self.queue = queue
        self.diagnostics = diagnostics
        self.options = options
        self.fusedEvolution = options["fusedEvolution"] != "0"
        self.batchBindings = options["batchBindings"] != "0"
        self.clock = AnimationClock(start:Double(options["time"] ?? "") ?? 0,mode:AnimationClock.Mode(rawValue:options["clock"] ?? "") ?? .continuous)
        self.time = clock.waveTime
        self.fixedStep = Float(options["fixedDt"] ?? "").flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.cacheUniforms = options["dynamicUniforms"] != "1"
        self.skipCloudOctaves = options["skipCloudOctaves"] != "0"
        self.packedJacobian = options["packedJacobian"] != "0"
        self.useSharedLighting = options["sharedLighting"] == "1" && options["perPixelLighting"] != "1"
        super.init()
        if CommandLine.arguments.contains("--profile") {
            profiler = GPUProfiler(device: device)
            if profiler == nil { print("GPU stage counters are unavailable on this device.") }
        }
        if options["fusedMips"] != "0" {
            mipmapRounding = (try? MipmapRounding.detect(device:device,queue:queue)) ?? .unsupported
            fusedMipmaps = mipmapRounding != .unsupported
        }
        if options["pruneCloudAA"] != "0" {
            specializedSkyAAMask = (value("clouds",0.4) > 0.001 ? 1 : 0) | (value("veil",0.36) > 0.001 ? 2 : 0)
            if verificationEnabled, let forcedMask = Int(options["testCloudAAMask"] ?? ""), (0...3).contains(forcedMask) {
                specializedSkyAAMask = forcedMask
            }
        }
        try createPipelines()
        try createResources()
        view.delegate = self
    }

    private func buffer(_ length: Int, _ label: String, privateStorage: Bool = false) throws -> MTLBuffer {
        guard let result = device.makeBuffer(length: length, options: privateStorage ? .storageModePrivate : .storageModeShared) else {
            throw OceanFailure(message: "Unable to allocate \(label) (\(length) bytes).")
        }
        result.label = label
        return result
    }

    private func texture(_ w: Int, _ h: Int, _ label: String, layers: Int = 1,
                         mips: Int = 1, format: MTLPixelFormat = .rgba16Float,
                         samples: Int = 1, transient: Bool = false, cube: Bool = false, renderOnly: Bool = false) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = cube ? .typeCube : samples > 1 ? .type2DMultisample : layers > 1 ? .type2DArray : .type2D
        descriptor.width = w; descriptor.height = h
        descriptor.arrayLength = cube ? 1 : layers
        descriptor.mipmapLevelCount = mips
        descriptor.pixelFormat = format
        descriptor.sampleCount = samples
        descriptor.storageMode = transient ? .memoryless : .private
        // Render-only textures need neither compute writes nor format reinterpretation.
        // Exact usage permits lossless GPU texture compression where supported.
        descriptor.usage = transient ? [.renderTarget] : renderOnly && options["narrowTextureUsage"] != "0"
            ? [.shaderRead, .renderTarget] : [.shaderRead, .shaderWrite, .renderTarget, .pixelFormatView]
        guard let result = device.makeTexture(descriptor: descriptor) else {
            throw OceanFailure(message: "Unable to allocate texture \(label).")
        }
        result.label = label
        return result
    }

    private func createPipelines() throws {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Shaders") else {
            throw OceanFailure(message: "The native Metal shaders are missing from the app bundle.")
        }
        let manifest = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        let compileOptions = MTLCompileOptions()
        compileOptions.languageVersion = .version2_3
        for name in manifest.keys.sorted() {
            if name.contains("MIPS_FUSED") && !fusedMipmaps { continue }
            let sourceURL = name == "OCEAN" && options["referenceOcean"] != nil
                    ? URL(fileURLWithPath:options["referenceOcean"]!) : root.appendingPathComponent(name + ".metal")
            var source = try String(contentsOf: sourceURL, encoding: .utf8)
            if name == "FFT_COLS" { source = "#define OCEAN_PACKED_JACOBIAN \(packedJacobian ? 1 : 0)\n"+source }
            if name == "OCEAN" { source = "#define OCEAN_SHARED_CUBIC \(options["sharedCubic"] == "0" ? 0 : 1)\n#define OCEAN_STABLE_TIME 0\n#define OCEAN_PACKED_JACOBIAN \(packedJacobian ? 1 : 0)\n#define OCEAN_PHYSICAL_GUARD 0\n#define OCEAN_COVERAGE \(verificationEnabled && options["coverage"] == "1" ? 1 : 0)\n#define OCEAN_PER_PIXEL_LIGHTING \(useSharedLighting ? 0 : 1)\n"+source }
            if name == "SKY_BG" { source = "#define CLOUD_AA_MASK 3\n"+source }
            if ["SKY_BG","ENV_CUBE","SUN_VIS"].contains(name) { source = "#define CLOUD_SKIP_ZERO \(skipCloudOctaves ? 1 : 0)\n#define CLOUD_STABLE_TIME 0\n"+source }
            do {
                let library = try device.makeLibrary(source: source, options: compileOptions)
                libraries[name] = library
                if name == "OCEAN" && options["legacyGuard"] != "1" {
                    let guardSource = source.replacingOccurrences(of:"#define OCEAN_PHYSICAL_GUARD 0",with:"#define OCEAN_PHYSICAL_GUARD 1")
                    libraries["OCEAN_GUARD"] = try device.makeLibrary(source:guardSource,options:compileOptions)
                }
                if name == "OCEAN" {
                    let stable = source.replacingOccurrences(of:"#define OCEAN_STABLE_TIME 0",with:"#define OCEAN_STABLE_TIME 1")
                    libraries["OCEAN_STABLE"] = try device.makeLibrary(source:stable,options:compileOptions)
                    let guarded = options["legacyGuard"] == "1" ? stable : stable.replacingOccurrences(of:"#define OCEAN_PHYSICAL_GUARD 0",with:"#define OCEAN_PHYSICAL_GUARD 1")
                    libraries["OCEAN_STABLE_GUARD"] = try device.makeLibrary(source:guarded,options:compileOptions)
                }
                if ["SKY_BG","ENV_CUBE","SUN_VIS"].contains(name) {
                    libraries[name+"_STABLE"] = try device.makeLibrary(source:source.replacingOccurrences(of:"#define CLOUD_STABLE_TIME 0",with:"#define CLOUD_STABLE_TIME 1"),options:compileOptions)
                }
                if name == "SKY_BG" && specializedSkyAAMask != 3 {
                    let specialized = source.replacingOccurrences(of:"#define CLOUD_AA_MASK 3",with:"#define CLOUD_AA_MASK \(specializedSkyAAMask)")
                    libraries["SKY_BG_PRUNED"] = try device.makeLibrary(source:specialized,options:compileOptions)
                    libraries["SKY_BG_PRUNED_STABLE"] = try device.makeLibrary(source:specialized.replacingOccurrences(of:"#define CLOUD_STABLE_TIME 0",with:"#define CLOUD_STABLE_TIME 1"),options:compileOptions)
                }
                if manifest[name] == ["main_"] {
                    let function: MTLFunction
                    if name.contains("MIPS_FUSED") {
                        let constants = MTLFunctionConstantValues()
                        var roundTowardZero = mipmapRounding == .towardZero
                        constants.setConstantValue(&roundTowardZero,type:.bool,index:0)
                        function = try library.makeFunction(name:"main_",constantValues:constants)
                    } else {
                        guard let kernel = library.makeFunction(name:"main_") else { throw OceanFailure(message:"Missing kernel \(name)") }
                        function = kernel
                    }
                    let threads: MTLSize
                    switch name {
                    case "FFT_ROWS", "FFT_COLS", "SIM_EVOLVE_ROWS": threads = MTLSize(width: 128, height: 1, depth: 1)
                    case "DISPLACEMENT_BOUNDS": threads = MTLSize(width:16,height:16,depth:1)
                    case "DISPLACEMENT_BOUNDS_FINAL": threads = MTLSize(width:8,height:1,depth:1)
                    case "SIM_INIT", "SIM_EVOLVE": threads = MTLSize(width: 16, height: 16, depth: 1)
                    case "SIM_MIPS_FUSED4", "ARRAY16_MIPS_FUSED4": threads = MTLSize(width:8,height:8,depth:1)
                    case "ARRAY16_MIPS_FUSED5": threads = MTLSize(width:16,height:16,depth:1)
                    case "LIGHTING": threads = MTLSize(width: 1, height: 1, depth: 1)
                    case "SUN_VIS": threads = MTLSize(width: 8, height: 1, depth: 1)
                    default: threads = MTLSize(width: 8, height: 8, depth: 1)
                    }
                    compute[name] = Pipeline(state: try device.makeComputePipelineState(function: function), threads: threads)
                    if let stable = libraries[name+"_STABLE"], let kernel = stable.makeFunction(name:"main_") {
                        compute[name+"_STABLE"] = Pipeline(state:try device.makeComputePipelineState(function:kernel),threads:threads)
                    }
                }
            } catch { throw OceanFailure(message: "Metal shader \(name): \(error.localizedDescription)") }
        }
        oceanPipeline = try renderPipeline("OCEAN", samples: 4, depth: true)
        oceanGuardPipeline = libraries["OCEAN_GUARD"] != nil ? try renderPipeline("OCEAN_GUARD",samples:4,depth:true) : oceanPipeline
        oceanStablePipeline = try renderPipeline("OCEAN_STABLE",samples:4,depth:true)
        oceanStableGuardPipeline = try renderPipeline("OCEAN_STABLE_GUARD",samples:4,depth:true)
        stableCachePipeline = try renderPipeline("SKY_BG_STABLE")
        skyPipeline = try renderPipeline("SKY_CACHED", samples: 4, depth: true)
        cachePipeline = try renderPipeline("SKY_BG")
        if specializedSkyAAMask != 3 {
            prunedCachePipeline = try renderPipeline("SKY_BG_PRUNED")
            prunedStableCachePipeline = try renderPipeline("SKY_BG_PRUNED_STABLE")
        }
        downPipeline = try renderPipeline("BLOOM_DOWN")
        upPipeline = try renderPipeline("BLOOM_UP", additive: true)
        compositePipeline = try renderPipeline("COMPOSITE", format: .bgra8Unorm)
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .greater; d.isDepthWriteEnabled = true
        oceanDepth = device.makeDepthStencilState(descriptor: d)
        d.depthCompareFunction = .equal; d.isDepthWriteEnabled = false
        skyDepth = device.makeDepthStencilState(descriptor: d)
    }

    private func renderPipeline(_ name: String, samples: Int = 1, depth: Bool = false,
                                additive: Bool = false, format: MTLPixelFormat = .rgba16Float) throws -> MTLRenderPipelineState {
        let d = MTLRenderPipelineDescriptor()
        d.label = name
        d.vertexFunction = libraries[name]!.makeFunction(name: "vs")
        d.fragmentFunction = libraries[name]!.makeFunction(name: "fs")
        d.colorAttachments[0].pixelFormat = format
        d.rasterSampleCount = samples
        if depth { d.depthAttachmentPixelFormat = .depth32Float }
        if additive {
            let c = d.colorAttachments[0]!
            c.isBlendingEnabled = true
            c.sourceRGBBlendFactor = .one; c.destinationRGBBlendFactor = .one
            c.sourceAlphaBlendFactor = .one; c.destinationAlphaBlendFactor = .one
        }
        return try device.makeRenderPipelineState(descriptor: d)
    }

    private func createResources() throws {
        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .linear; sampler.magFilter = .linear; sampler.mipFilter = .linear
        clampSampler = device.makeSamplerState(descriptor: sampler)
        sampler.sAddressMode = .repeat; sampler.tAddressMode = .repeat
        simSampler = device.makeSamplerState(descriptor: sampler)
        sampler.maxAnisotropy = 4
        repeatSampler = device.makeSamplerState(descriptor: sampler)
        sampler.maxAnisotropy = 1; sampler.mipFilter = .notMipmapped
        sampler.sAddressMode = .clampToEdge; sampler.tAddressMode = .clampToEdge
        linearSampler = device.makeSamplerState(descriptor: sampler)
        frameBuffer = try buffer(384+AnimationClock.cloudShiftCount*16, "frame")
        displacementBounds = try buffer(16,"displacement guard bounds")
        partialBounds = try buffer(16*16*cascades*16,"partial displacement bounds",privateStorage:true)
        simBuffer = try buffer(224, "spectrum parameters")
        foamBuffer = try buffer(144, "foam parameters")
        atmoBuffer = try buffer(16, "atmosphere parameters")
        compositeBuffer = try buffer(32, "tone mapping")
        sizesBuffer = try buffer(128, "shader buffer sizes")
        // Runtime arrays have explicit, CPU-validated indices. This metadata is
        // retained by the migrated Metal function signatures, but is not read.
        memset(sizesBuffer.contents(), 0, sizesBuffer.length)
        sunBuffer = try buffer(16, "sun visibility", privateStorage: true)
        lightingTexture = try texture(5,1,"shared ocean lighting",format:.rgba32Float)
        let bytes = n * n * cascades * 16
        h0 = try buffer(bytes, "initial spectrum", privateStorage: true)
        if !fusedEvolution {
            specA = try buffer(bytes, "spectrum A", privateStorage: true)
            specB = try buffer(bytes, "spectrum B", privateStorage: true)
        }
        tmpA = try buffer(bytes, "FFT temporary A", privateStorage: true)
        tmpB = try buffer(bytes, "FFT temporary B", privateStorage: true)
        disp = try texture(n, n, "displacement", layers: cascades, mips: 9)
        deriv = try texture(n, n, "wave derivatives", layers: cascades, mips: 9)
        moments = try texture(n, n, "slope moments", layers: cascades, mips: 9)
        foamDetail = try texture(512, 512, "foam detail", mips: 10, format: .rgba8Unorm)
        for i in 0..<2 { foam.append(try texture(foamSize, foamSize, "foam \(i)", layers: 2, mips: 10)) }
        trans = try texture(256, 64, "transmittance")
        multipleScatter = try texture(32, 32, "multiple scattering")
        skyLUT = try texture(256, 144, "sky lookup")
        environment = try texture(128, 128, "environment", mips: 8, cube: true)
        for (name, t) in [("disp", disp!), ("deriv", deriv!), ("moments", moments!), ("detail", foamDetail!), ("foam0", foam[0]), ("foam1", foam[1]), ("env", environment!)] {
            let count = name == "env" ? 6 : t.arrayLength
            let type: MTLTextureType = (name == "env" || t.arrayLength > 1) ? .type2DArray : .type2D
            mipViews[name] = try (0..<t.mipmapLevelCount).map { mip in
                guard let view = t.makeTextureView(pixelFormat: t.pixelFormat, textureType: type, levels: mip..<mip+1, slices: 0..<count) else {
                    throw OceanFailure(message: "Cannot create \(name) mip \(mip)")
                }
                return view
            }
        }
        waveMipResources = [0,4].map { base in
            ["disp","deriv","moments"].flatMap { name in (base...base+4).map { Resource.texture(mip(name,$0)) } }
        }
        foamMipResources = (0..<2).map { index in
            [(0...4).map { Resource.texture(mip("foam\(index)",$0)) }, (4...9).map { Resource.texture(mip("foam\(index)",$0)) }]
        }
        waveBindings = waveMipResources.map(ResourceBindings.init)
        foamBindings = foamMipResources.map { $0.map(ResourceBindings.init) }
        bloomUniforms = try (0..<bloomLevels*2).map { try buffer(16, "bloom uniform \($0)") }
        resourcePlans.evolveRows = ResourceBindings([.buffer(simBuffer),.buffer(h0),.buffer(tmpA),.buffer(tmpB)])
        if !fusedEvolution { resourcePlans.evolve = ResourceBindings([.buffer(simBuffer),.buffer(h0),.buffer(specA),.buffer(specB)]) }
        if !fusedEvolution { resourcePlans.fftRows = ResourceBindings([.buffer(specA),.buffer(specB),.buffer(tmpA),.buffer(tmpB)]) }
        resourcePlans.fftCols = ResourceBindings([.buffer(tmpA),.buffer(tmpB),.texture(mip("disp",0)),.texture(mip("deriv",0)),.texture(mip("moments",0))])
        resourcePlans.bounds = ResourceBindings([.texture(mip("disp",0)),.buffer(partialBounds)])
        resourcePlans.boundsFinal = ResourceBindings([.buffer(partialBounds),.buffer(displacementBounds)])
        resourcePlans.foamUpdate = (0..<2).map { foamIndex in ResourceBindings([.buffer(foamBuffer),.texture(mip("foam\(1-foamIndex)",0)),.texture(mip("foam\(foamIndex)",0)),.texture(disp),.texture(deriv),.sampler(simSampler),.sampler(simSampler)]) }
        resourcePlans.skyLUT = ResourceBindings([.buffer(frameBuffer),.texture(trans),.texture(multipleScatter),.sampler(clampSampler),.texture(skyLUT)])
        resourcePlans.sun = ResourceBindings([.buffer(frameBuffer),.texture(trans),.texture(skyLUT),.sampler(clampSampler),.buffer(sunBuffer)])
        resourcePlans.environment = ResourceBindings([.buffer(frameBuffer),.texture(trans),.texture(skyLUT),.sampler(clampSampler),.texture(mip("env",0))])
        resourcePlans.environmentMips = (1..<8).map { m in ResourceBindings([.texture(mip("env",m-1)),.texture(mip("env",m)),.buffer(frameBuffer)]) }
        resourcePlans.lighting = ResourceBindings([.buffer(frameBuffer),.texture(trans),.texture(environment),.sampler(clampSampler),.buffer(sunBuffer),.texture(lightingTexture)])
        resourcePlans.visibleSky = ResourceBindings([.buffer(frameBuffer),.texture(trans),.texture(skyLUT),.sampler(clampSampler)])
        resourcePlans.ocean = (0..<2).map { foamIndex in ResourceBindings([.buffer(frameBuffer),.texture(trans),.texture(skyLUT),.sampler(clampSampler),.texture(disp),.texture(deriv),.texture(moments),.texture(foamDetail),.texture(environment),.sampler(repeatSampler),.texture(foam[foamIndex]),.buffer(sunBuffer),.texture(lightingTexture)]) }
    }

    private func createGrid() throws {
        let mesh = ViewportMesh(columns:columns,rows:rows,forceWideIndices:options["wideIndices"] == "1")
        let next = try buffer(mesh.indices.count,"viewport grid indices")
        mesh.indices.withUnsafeBytes { next.contents().copyMemory(from:$0.baseAddress!,byteCount:$0.count) }
        indexBuffer = next
        indexType = mesh.indexBytes == 2 ? .uint16 : .uint32
    }

    private func write(_ values: [Float], to buffer: MTLBuffer) {
        values.withUnsafeBytes { buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
    }

    private func value(_ name: String, _ fallback: Float) -> Float { Float(options[name] ?? "") ?? fallback }

    private func writeUniforms(dt: Float) {
        if cacheUniforms && !uniformsDirty {
            // Shared buffers are protected by the single-frame semaphore. The
            // fixed camera and launch-time settings change only after a resize.
            let frame = frameBuffer.contents().assumingMemoryBound(to:Float.self)
            frame[19] = clock.detailTime; frame[23] = Float(envFace)
            frame[70] = Float(frameIndex); frame[95] = clock.detailTime
            let sim = simBuffer.contents().assumingMemoryBound(to:Float.self)
            sim[52] = time; sim[53] = dt
            let foam = foamBuffer.contents().assumingMemoryBound(to:Float.self)
            foam[10] = dt
            // Clear the initial reset sentinel after the first completed frame.
            let snap = foamBuffer.contents().assumingMemoryBound(to:Int32.self)
            snap[2] = 0; snap[3] = 0; snap[6] = 0; snap[7] = 0
            compositeBuffer.contents().assumingMemoryBound(to:Float.self)[2] = Float(frameIndex%64)
            return
        }
        let d2r = Float.pi / 180
        let pitch = -5.5 * d2r, tanY = tan(58 * d2r / 2), tanX = tanY * Float(width) / Float(height)
        let cp = cos(pitch), sp = sin(pitch)
        let right = SIMD3<Float>(1, 0, 0), forward = SIMD3<Float>(0, sp, -cp), up = SIMD3<Float>(0, cp, sp)
        let view = simd_float4x4(columns: (SIMD4(right.x, up.x, -forward.x, 0), SIMD4(right.y, up.y, -forward.y, 0), SIMD4(right.z, up.z, -forward.z, 0), SIMD4(0,0,0,1)))
        let projection = simd_float4x4(columns: (SIMD4(1/tanX,0,0,0), SIMD4(0,1/tanY,0,0), SIMD4(0,0,0,-1), SIMD4(0,0,0.05,0)))
        let matrix = projection * view
        var f = [Float](repeating: 0, count: 96)
        withUnsafeBytes(of: matrix) { bytes in
            let floats = bytes.bindMemory(to: Float.self)
            for i in 0..<16 { f[i] = floats[i] }
        }
        f[17] = 2.4; f[19] = clock.detailTime
        f[20] = tanX; f[23] = Float(envFace)
        f[25] = up.y * tanY; f[26] = up.z * tanY
        f[29] = forward.y; f[30] = forward.z
        let elevation = value("sunElev", 2.6) * d2r, azimuth = value("sunAzim", 4) * d2r
        f[32] = sin(azimuth)*cos(elevation); f[33] = sin(elevation); f[34] = -cos(azimuth)*cos(elevation); f[35] = 14
        f[36] = Float(width); f[37] = Float(height); f[38] = 1/Float(width); f[39] = 1/Float(height)
        for c in 0..<cascades { f[40+c] = cascadeLengths[c]; f[48+c] = 1/cascadeLengths[c] }
        let wind = value("windSpeed", 7), windDirection = value("windDir", 118) * d2r
        f[56] = cos(windDirection); f[57] = sin(windDirection); f[58] = wind
        f[64] = Float(columns); f[65] = Float(rows); f[66] = 128; f[67] = 1024
        f[68] = value("exposure", 1.35); f[69] = value("bloom", 0.1); f[70] = Float(frameIndex); f[71] = value("dbg", 0)
        let haze = value("haze", 3), turbidity = value("turbidity", 1.6)
        f[72] = haze; f[73] = 0.01; f[74] = value("veil", 0.36); f[75] = 0.9
        f[76] = 0.016*turbidity; f[77] = 0.080*turbidity; f[78] = 0.096*turbidity; f[79] = 0.0024
        f[80] = 0.035; f[81] = 0.120; f[82] = 0.085; f[83] = 2.6
        f[84] = 0.36+0.12*value("foam", 1); f[85] = 2.5; f[86] = 1; f[87] = 1
        f[88] = (5.802e-3+4.40e-3*haze)*1e-3; f[89] = (13.558e-3+4.40e-3*haze)*1e-3; f[90] = (33.1e-3+4.40e-3*haze)*1e-3; f[91] = 1.1e-4
        f[92] = 1.5; f[93] = value("clouds", 0.4); f[94] = 2.2; f[95] = clock.detailTime
        write(f, to: frameBuffer)
        var s = [Float](repeating: 0, count: 56)
        for c in 0..<cascades {
            s[c] = cascadeLengths[c]
            s[8+c] = c == 0 ? .pi/cascadeLengths[c] : (2 * .pi * 6)/cascadeLengths[c]
            s[16+c] = c < cascades-1 ? (2 * .pi * 6)/cascadeLengths[c+1] : (.pi*Float(n)/cascadeLengths[c])*0.98
        }
        s[40] = wind; s[41] = windDirection; s[42] = 90000; s[43] = 3.3
        s[44] = value("swellHs", 1.8); s[45] = 94*d2r; s[46] = sqrt(9.81*2 * .pi/120); s[47] = 48
        s[48] = value("choppy", 1.25); s[49] = 0.0012; s[50] = 600; s[51] = 1
        s[52] = time; s[53] = dt; s[54] = 2.2; s[55] = 1
        write(s, to: simBuffer)
        write([haze,0,0,0], to: atmoBuffer)
        var foamValues = [Float](repeating: 0, count: 36)
        for layer in 0..<2 {
            if foamFirst { foamValues[layer*4+2] = Float(bitPattern: UInt32(100000)); foamValues[layer*4+3] = Float(bitPattern: UInt32(100000)) }
            foamValues[8+layer] = (layer == 0 ? 128 : 1024)/Float(foamSize)
        }
        foamValues[10] = dt; foamValues[11] = 0.22
        foamValues[12] = 0.52+0.16*value("foam", 1); foamValues[13] = 2; foamValues[14] = 1
        foamValues[15] = tanX * 1.15
        for c in 0..<cascades { foamValues[16+c] = cascadeLengths[c]; foamValues[24+c] = 1/cascadeLengths[c] }
        foamValues[32] = cos(windDirection)*0.03*wind; foamValues[33] = sin(windDirection)*0.03*wind
        write(foamValues, to: foamBuffer)
        foamFirst = false
        write([value("exposure",1.35), value("bloom",0.1), Float(frameIndex%64), 0.1, 1.05, 1.06, -0.19, 0], to: compositeBuffer)
        uniformsDirty = false
    }

    private func writeTemporalUniforms(updateClouds: Bool) {
        let frame = frameBuffer.contents().assumingMemoryBound(to:Float.self)
        guard clock.stableDetails else { frame[63] = 0; return }
        let phases = clock.detailPhases(wind:SIMD2(frame[56],frame[57]))
        for i in 0..<4 { frame[60+i] = phases[i] }
        if updateClouds {
            clock.writeCloudShifts(to:UnsafeMutableBufferPointer(start:frameBuffer.contents().advanced(by:384).assumingMemoryBound(to:UInt32.self),count:AnimationClock.cloudShiftCount*4))
        }
    }

    // Immutable lists retain resource identity, while uniforms update in place.
    // Reference mode lazily reconstructs the original list for exact comparisons.
    @inline(__always)
    private func planned(_ resources: ResourceBindings?, fallback: @autoclosure () -> [Resource]) -> BindingList {
        batchBindings ? .batched(resources!) : .individual(fallback())
    }

    private enum BindingList {
        case individual([Resource]), batched(ResourceBindings)
    }

    private func bind(_ resources: BindingList, to encoder: MTLComputeCommandEncoder) {
        switch resources {
        case .individual(let list): bind(list,to:encoder)
        case .batched(let plan):
            if options["verboseBindings"] == "1" { bind(plan.resources,to:encoder) }
            else { plan.bind(to:encoder) }
        }
    }

    private func bind(_ resources: BindingList, to encoder: MTLRenderCommandEncoder, vertexSlots: UInt32 = 0) {
        switch resources {
        case .individual(let list): bind(list,to:encoder,vertexSlots:vertexSlots)
        case .batched(let plan):
            if options["verboseBindings"] == "1" { bind(plan.resources,to:encoder,vertexSlots:vertexSlots) }
            else { plan.bind(to:encoder,vertexSlots:vertexSlots) }
        }
    }

    private func bind(_ resources: [Resource], to encoder: MTLComputeCommandEncoder) {
        for (i, resource) in resources.enumerated() {
            switch resource {
            case .buffer(let b): encoder.setBuffer(b, offset: 0, index: i)
            case .texture(let t): encoder.setTexture(t, index: i)
            case .sampler(let s): encoder.setSamplerState(s, index: i)
            }
        }
        if options["verboseBindings"] == "1" { encoder.setBuffer(sizesBuffer, offset: 0, index: 30) }
    }

    // Fullscreen vertex shaders consume only vertex_id. Ocean vertices need
    // frame uniforms, displacement, and the repeat sampler (slots 0, 4, 9).
    // Bind fragment resources normally; avoid redundant vertex-stage calls.
    private func bind(_ resources: [Resource], to encoder: MTLRenderCommandEncoder, vertexSlots: UInt32 = 0) {
        let legacy = options["verboseBindings"] == "1"
        for (i, resource) in resources.enumerated() {
            let vertex = legacy || vertexSlots & (1 << i) != 0
            switch resource {
            case .buffer(let b):
                if vertex { encoder.setVertexBuffer(b, offset: 0, index: i) }
                encoder.setFragmentBuffer(b, offset: 0, index: i)
            case .texture(let t):
                if vertex { encoder.setVertexTexture(t, index: i) }
                encoder.setFragmentTexture(t, index: i)
            case .sampler(let s):
                if vertex { encoder.setVertexSamplerState(s, index: i) }
                encoder.setFragmentSamplerState(s, index: i)
            }
        }
        // No render shader declares the compute buffer-size table.
        if legacy {
            encoder.setVertexBuffer(sizesBuffer, offset: 0, index: 30)
            encoder.setFragmentBuffer(sizesBuffer, offset: 0, index: 30)
        }
    }

    private func dispatch(_ name: String, _ encoder: MTLComputeCommandEncoder, _ resources: [Resource], groups: MTLSize) {
        let pipeline = compute[name]!
        encoder.setComputePipelineState(pipeline.state)
        bind(resources, to: encoder)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: pipeline.threads)
        // Both makeCompute paths create serial encoders. Metal preserves
        // dispatch order; explicit memory barriers on these encoders are ignored.
    }

    private func dispatch(_ name: String, _ encoder: MTLComputeCommandEncoder, _ resources: BindingList, groups: MTLSize) {
        let pipeline = compute[name]!
        encoder.setComputePipelineState(pipeline.state)
        bind(resources, to: encoder)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: pipeline.threads)
        // Both makeCompute paths create serial encoders. Metal preserves
        // dispatch order; explicit memory barriers on these encoders are ignored.
    }

    private func groups(_ w: Int, _ h: Int, _ layers: Int = 1) -> MTLSize { MTLSize(width: (w+7)/8, height: (h+7)/8, depth: layers) }
    private func mip(_ name: String, _ level: Int) -> MTLTexture { mipViews[name]![level] }

    private func updateSize(_ view: MTKView) throws {
        let layout: ViewportLayout
        if verificationEnabled, let sequence = Int(options["resizeSequence"] ?? ""), (1...2).contains(sequence) {
            // Exercise replacement of cached screen-sized resources in one GPU run.
            let layouts = [(1280.0,800.0),(759.0,1349.0),(1908.0,537.0),sequence == 1 ? (1280.0,800.0) : (253.0,4048.0)]
            let size = layouts[min(frameIndex/2,layouts.count-1)]
            layout = ViewportLayout(pointWidth:size.0,pointHeight:size.1,backingScale:1)
        } else if (verificationEnabled || benchmarkEnabled),
           let testWidth = Double(options["renderWidth"] ?? ""), let testHeight = Double(options["renderHeight"] ?? "") {
            // Verification can exercise real portrait/ultrawide GPU targets even
            // when AppKit constrains the test window to the attached display.
            layout = ViewportLayout(pointWidth:testWidth,pointHeight:testHeight,backingScale:1)
        } else {
            layout = ViewportLayout(pointWidth:Double(view.bounds.width),pointHeight:Double(view.bounds.height),
                                    backingScale:Double(view.window?.backingScaleFactor ?? 2))
        }
        let w = layout.width, h = layout.height
        guard w != width || h != height else { return }
        if indexBuffer == nil || columns != layout.columns || rows != layout.rows {
            columns = layout.columns; rows = layout.rows
            try createGrid()
        }
        width = w; height = h
        if verificationEnabled && options["resizeSequence"] != nil { verifiedResizeLayouts.append([w,h]) }
        uniformsDirty = true
        view.drawableSize = CGSize(width: w, height: h)
        hdr = try texture(w, h, "HDR scene", renderOnly: true)
        msaa = try texture(w, h, "transient MSAA", samples: 4, transient: true)
        depth = try texture(w, h, "transient depth", format: .depth32Float, samples: 4, transient: true)
        cachedSky = try texture(max(1,w*3/4), max(1,h*3/4), "cached sky", renderOnly: true)
        bloom = try (0..<bloomLevels).map { try texture(max(1,w >> ($0+1)), max(1,h >> ($0+1)), "bloom \($0)", renderOnly: true) }
        for i in 0..<bloomLevels {
            let sourceW = i == 0 ? w : bloom[i-1].width, sourceH = i == 0 ? h : bloom[i-1].height
            write([1/Float(sourceW),1/Float(sourceH),i == 0 ? 1 : 0,0], to: bloomUniforms[i])
            write([1/Float(bloom[i].width),1/Float(bloom[i].height),1,1], to: bloomUniforms[bloomLevels+i])
        }
        resourcePlans.sky = ResourceBindings([.texture(cachedSky),.sampler(clampSampler)])
        resourcePlans.bloomDown = (0..<bloomLevels).map { m in ResourceBindings([.texture(m == 0 ? hdr : bloom[m-1]),.sampler(linearSampler),.buffer(bloomUniforms[m])]) }
        resourcePlans.bloomUp = (1..<bloomLevels).map { m in ResourceBindings([.texture(bloom[m]),.sampler(linearSampler),.buffer(bloomUniforms[bloomLevels+m])]) }
        resourcePlans.composite = ResourceBindings([.texture(hdr),.texture(bloom[0]),.sampler(linearSampler),.buffer(compositeBuffer)])
        cacheDirty = true
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { cacheDirty = true }

    func draw(in view: MTKView) {
        guard !isPaused, gate.wait(timeout: .now()) == .success else { return }
        var committed = false
        defer { if !committed { gate.signal() } }
        do { try updateSize(view) } catch { record(error.localizedDescription); return }
        guard let drawable = view.currentDrawable else { return }
        let descriptor = MTLCommandBufferDescriptor()
        if diagnostics { descriptor.errorOptions = .encoderExecutionStatus }
        guard let command = queue.makeCommandBuffer(descriptor: descriptor) else { record("Cannot allocate command buffer"); return }
        command.label = "Ocean frame \(frameIndex)"
        let now = CACurrentMediaTime()
        let cpuThreadStart = benchmarkEnabled ? threadCPUTimeMilliseconds() : 0
        let elapsedStep = fixedStep.map(Double.init) ?? (lastTime == 0 ? 1.0/30 : min(0.1,now-lastTime))
        let dt = Float(elapsedStep)
        lastTime = now; clock.advance(by:elapsedStep); time = clock.waveTime; frameIndex += 1
        let cadence = fixedStep == nil ? now : Double(frameIndex)*Double(dt)
        writeUniforms(dt: dt)
        writeTemporalUniforms(updateClouds:!initialized || cacheDirty || cadence-lastCache >= 0.125 || cadence-lastEnvironment >= 0.1 || cadence-lastSky >= 0.25)
        profiler?.beginFrame()
        guard var c = makeCompute(command, label: "waves") else { return }
        c.label = "Waves, atmosphere, and visible foam"
        if !initialized {
            dispatch("SIM_INIT", c, [.buffer(simBuffer),.buffer(h0)], groups: MTLSize(width: n/16,height: n/16,depth: cascades))
            dispatch("FOAM_TEX", c, [.texture(mip("detail",0))], groups: groups(512,512))
            for m in 1..<10 { dispatch("RGBA8_MIPS", c, [.texture(mip("detail",m-1)),.texture(mip("detail",m))], groups: groups(max(1,512>>m),max(1,512>>m))) }
            dispatch("TRANS_LUT", c, [.buffer(atmoBuffer),.texture(trans)], groups: groups(256,64))
            dispatch("MS_LUT", c, [.buffer(atmoBuffer),.texture(trans),.sampler(clampSampler),.texture(multipleScatter)], groups: groups(32,32))
        }
        if fusedEvolution {
            dispatch("SIM_EVOLVE_ROWS",c,planned(resourcePlans.evolveRows, fallback: [.buffer(simBuffer),.buffer(h0),.buffer(tmpA),.buffer(tmpB)]),groups:MTLSize(width:n,height:1,depth:cascades))
        } else {
            dispatch("SIM_EVOLVE", c, planned(resourcePlans.evolve, fallback: [.buffer(simBuffer),.buffer(h0),.buffer(specA),.buffer(specB)]), groups: MTLSize(width:n/16,height:n/16,depth:cascades))
            dispatch("FFT_ROWS", c, planned(resourcePlans.fftRows, fallback: [.buffer(specA),.buffer(specB),.buffer(tmpA),.buffer(tmpB)]), groups: MTLSize(width:n,height:1,depth:cascades))
        }
        dispatch("FFT_COLS", c, planned(resourcePlans.fftCols, fallback: [.buffer(tmpA),.buffer(tmpB),.texture(mip("disp",0)),.texture(mip("deriv",0)),.texture(mip("moments",0))]), groups: MTLSize(width:n,height:1,depth:cascades))
        if fusedMipmaps {
            for (index,base) in [0,4].enumerated() {
                dispatch("SIM_MIPS_FUSED4",c,planned(waveBindings[index],fallback:waveMipResources[index]),groups:MTLSize(width:max(1,n>>(base+4)),height:max(1,n>>(base+4)),depth:cascades))
            }
        } else {
            for m in 1..<9 {
                dispatch("SIM_MIPS",c,[.texture(mip("disp",m-1)),.texture(mip("deriv",m-1)),.texture(mip("moments",m-1)),.texture(mip("disp",m)),.texture(mip("deriv",m)),.texture(mip("moments",m))],groups:groups(max(1,n>>m),max(1,n>>m),cascades))
            }
        }
        if width*2 < height && options["legacyGuard"] != "1" {
            dispatch("DISPLACEMENT_BOUNDS",c,planned(resourcePlans.bounds, fallback: [.texture(mip("disp",0)),.buffer(partialBounds)]),groups:MTLSize(width:16,height:16,depth:cascades))
            dispatch("DISPLACEMENT_BOUNDS_FINAL",c,planned(resourcePlans.boundsFinal, fallback: [.buffer(partialBounds),.buffer(displacementBounds)]),groups:MTLSize(width:1,height:1,depth:1))
        }
        if profiler != nil {
            c.endEncoding()
            guard let next = makeCompute(command,label:"foam") else { return }
            c = next
        }
        foamIndex = 1-foamIndex
        dispatch("FOAM_UPDATE", c, planned(resourcePlans.foamUpdate[foamIndex], fallback: [.buffer(foamBuffer),.texture(mip("foam\(1-foamIndex)",0)),.texture(mip("foam\(foamIndex)",0)),.texture(disp),.texture(deriv),.sampler(simSampler),.sampler(simSampler)]), groups: groups(foamSize,foamSize,2))
        if fusedMipmaps {
            dispatch("ARRAY16_MIPS_FUSED4",c,planned(foamBindings[foamIndex][0],fallback:foamMipResources[foamIndex][0]),groups:MTLSize(width:foamSize/16,height:foamSize/16,depth:2))
            dispatch("ARRAY16_MIPS_FUSED5",c,planned(foamBindings[foamIndex][1],fallback:foamMipResources[foamIndex][1]),groups:MTLSize(width:1,height:1,depth:2))
        } else {
            for m in 1..<10 { dispatch("ARRAY16_MIPS",c,[.texture(mip("foam\(foamIndex)",m-1)),.texture(mip("foam\(foamIndex)",m))],groups:groups(max(1,foamSize>>m),max(1,foamSize>>m),2)) }
        }
        let lightingChanged = !initialized || cadence-lastSky >= 0.25 || cadence-lastEnvironment >= 0.1
        if !initialized || cadence-lastSky >= 0.25 {
            if profiler != nil {
                c.endEncoding()
                guard let next = makeCompute(command,label:"atmosphere") else { return }
                c = next
            }
            dispatch("SKYVIEW_LUT", c, planned(resourcePlans.skyLUT, fallback: [.buffer(frameBuffer),.texture(trans),.texture(multipleScatter),.sampler(clampSampler),.texture(skyLUT)]), groups: groups(256,144))
            dispatch(clock.stableDetails ? "SUN_VIS_STABLE" : "SUN_VIS", c, planned(resourcePlans.sun, fallback: [.buffer(frameBuffer),.texture(trans),.texture(skyLUT),.sampler(clampSampler),.buffer(sunBuffer)]), groups: MTLSize(width:1,height:1,depth:1))
            lastSky = cadence
        }
        if !initialized || cadence-lastEnvironment >= 0.1 {
            if profiler != nil {
                c.endEncoding()
                guard let next = makeCompute(command,label:"environment") else { return }
                c = next
            }
            let faces = initialized ? 1 : 6
            dispatch(clock.stableDetails ? "ENV_CUBE_STABLE" : "ENV_CUBE", c, planned(resourcePlans.environment, fallback: [.buffer(frameBuffer),.texture(trans),.texture(skyLUT),.sampler(clampSampler),.texture(mip("env",0))]), groups: groups(128,128,faces))
            for m in 1..<8 { dispatch("CUBE_MIPS", c, planned(resourcePlans.environmentMips[m-1], fallback: [.texture(mip("env",m-1)),.texture(mip("env",m)),.buffer(frameBuffer)]), groups: groups(max(1,128>>m),max(1,128>>m),faces)) }
            envFace = (envFace+1)%6; lastEnvironment = cadence
        }
        if useSharedLighting && lightingChanged {
            if profiler != nil {
                c.endEncoding()
                guard let next = makeCompute(command,label:"shared lighting") else { return }
                c = next
            }
            dispatch("LIGHTING",c,planned(resourcePlans.lighting, fallback: [.buffer(frameBuffer),.texture(trans),.texture(environment),.sampler(clampSampler),.buffer(sunBuffer),.texture(lightingTexture)]),groups:MTLSize(width:1,height:1,depth:1))
        }
        c.endEncoding()
        if cacheDirty || cadence-lastCache >= 0.125 {
            render(command, target: cachedSky, pipeline: visibleSkyPipeline(), label: "visible sky", resources: planned(resourcePlans.visibleSky, fallback: [.buffer(frameBuffer),.texture(trans),.texture(skyLUT),.sampler(clampSampler)]), skyScissor:options["fullSky"] != "1")
            cacheDirty = false; lastCache = cadence; cachedSkyElapsed = clock.elapsed
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaa
        pass.colorAttachments[0].resolveTexture = hdr
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.depthAttachment.texture = depth
        pass.depthAttachment.clearDepth = 0
        pass.depthAttachment.loadAction = .clear; pass.depthAttachment.storeAction = .dontCare
        profiler?.render(pass,label:"ocean and sky")
        guard let r = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        r.label = "Viewport ocean (\(triangleCount) triangles)"
        let needsGuard = width*2 < height && options["legacyGuard"] != "1"
        r.setRenderPipelineState(clock.stableDetails ? (needsGuard ? oceanStableGuardPipeline : oceanStablePipeline) : (needsGuard ? oceanGuardPipeline : oceanPipeline)); r.setDepthStencilState(oceanDepth)
        if needsGuard { r.setVertexBuffer(displacementBounds,offset:0,index:13) }
        r.setCullMode(.none)
        bind(planned(resourcePlans.ocean[foamIndex], fallback: [.buffer(frameBuffer),.texture(trans),.texture(skyLUT),.sampler(clampSampler),.texture(disp),.texture(deriv),.texture(moments),.texture(foamDetail),.texture(environment),.sampler(repeatSampler),.texture(foam[foamIndex]),.buffer(sunBuffer),.texture(lightingTexture)]), to: r, vertexSlots: (1 << 0) | (1 << 4) | (1 << 9))
        if !(verificationEnabled && options["skyOnly"] == "1") {
            r.drawIndexedPrimitives(type: .triangle, indexCount: triangleCount*3, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: 0)
        }
        if !(verificationEnabled && options["coverage"] == "1") {
            r.setRenderPipelineState(skyPipeline); r.setDepthStencilState(skyDepth)
            bind(planned(resourcePlans.sky, fallback: [.texture(cachedSky),.sampler(clampSampler)]), to: r)
            r.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        r.endEncoding()
        for m in 0..<bloomLevels {
            render(command, target: bloom[m], pipeline: downPipeline, label: "bloom down", resources: planned(resourcePlans.bloomDown[m], fallback: [.texture(m == 0 ? hdr : bloom[m-1]),.sampler(linearSampler),.buffer(bloomUniforms[m])]))
        }
        for m in stride(from: bloomLevels-1, through: 1, by: -1) {
            render(command, target: bloom[m-1], pipeline: upPipeline, label: "bloom up", resources: planned(resourcePlans.bloomUp[m-1], fallback: [.texture(bloom[m]),.sampler(linearSampler),.buffer(bloomUniforms[bloomLevels+m])]), load: .load)
        }
        render(command, target: drawable.texture, pipeline: compositePipeline, label: "composite", resources: planned(resourcePlans.composite, fallback: [.texture(hdr),.texture(bloom[0]),.sampler(linearSampler),.buffer(compositeBuffer)]))
        let verify = verificationEnabled && frameIndex == 8
        let readbacks: [Readback]
        do { readbacks = verify ? try encodeReadbacks(command, display:drawable.texture) : [] }
        catch { record(error.localizedDescription); return }
        command.present(drawable)
        let profileLabels = profiler?.labels ?? []
        let renderedFrame = frameIndex
        let cpuEncodeMs = benchmarkEnabled ? (CACurrentMediaTime()-now)*1000 : 0
        let threadCPUEncodeMs = benchmarkEnabled ? threadCPUTimeMilliseconds()-cpuThreadStart : 0
        command.addCompletedHandler { [weak self] completed in
            guard let self else { return }
            let stageTimes = self.profiler?.resolve(labels: profileLabels) ?? [:]
            let elapsed = (completed.gpuEndTime-completed.gpuStartTime)*1000
            DispatchQueue.main.async {
                if completed.status == .error { self.record(completed.error?.localizedDescription ?? "Metal command failed") }
                if elapsed > 0 { self.gpuMilliseconds = self.gpuMilliseconds == 0 ? elapsed : self.gpuMilliseconds*0.8+elapsed*0.2 }
                self.profiler?.record(stageTimes, frame:renderedFrame)
                self.frames += 1
                if self.benchmarkEnabled && renderedFrame > 60 { self.benchmarkTimes.append(elapsed); self.benchmarkCPUTimes.append(cpuEncodeMs); self.benchmarkThreadCPUTimes.append(threadCPUEncodeMs) }
                if self.benchmarkEnabled && self.frames >= (Int(self.options["frames"] ?? "") ?? 180) {
                    self.finishBenchmark()
                }
                if verify { self.verify(readbacks) }
            }
            self.gate.signal()
        }
        initialized = true
        committed = true
        command.commit()
    }

    private func visibleSkyPipeline() -> MTLRenderPipelineState {
        let full = clock.stableDetails ? stableCachePipeline! : cachePipeline!
        guard let specialized = clock.stableDetails ? prunedStableCachePipeline : prunedCachePipeline else {
            lastSkyAAMask = 3
            return full
        }
        let frame = frameBuffer.contents().assumingMemoryBound(to:Float.self)
        let activeMask = (frame[93] > 0.001 ? 1 : 0) | (frame[74] > 0.001 ? 2 : 0)
        // Newly enabled layers use the full shader if their AA was omitted.
        if (activeMask & ~specializedSkyAAMask) == 0 {
            lastSkyAAMask = specializedSkyAAMask
            return specialized
        }
        lastSkyAAMask = 3
        return full
    }

    private func makeCompute(_ command: MTLCommandBuffer, label: String) -> MTLComputeCommandEncoder? {
        let encoder = profiler.map { command.makeComputeCommandEncoder(descriptor:$0.compute(label)) }
            ?? command.makeComputeCommandEncoder()
        // The size table is immutable and shared by every kernel in this encoder.
        if options["verboseBindings"] != "1" { encoder?.setBuffer(sizesBuffer,offset:0,index:30) }
        return encoder
    }

    private func render(_ command: MTLCommandBuffer, target: MTLTexture, pipeline: MTLRenderPipelineState,
                        label: String, resources: BindingList, load: MTLLoadAction = .clear, skyScissor: Bool = false) {
        let p = MTLRenderPassDescriptor()
        p.colorAttachments[0].texture = target
        p.colorAttachments[0].loadAction = load; p.colorAttachments[0].storeAction = .store
        profiler?.render(p,label:label)
        guard let e = command.makeRenderCommandEncoder(descriptor: p) else { record("Cannot create render pass"); return }
        e.setRenderPipelineState(pipeline)
        if skyScissor && (width*2 >= height || options["legacyGuard"] != "1") {
            // Wave-bounded guard geometry keeps narrow views covered as well.

            // Horizon y is fixed by camera pitch/FOV, independent of aspect.
            // Keep a conservative margin below it; opaque ocean covers the rest.
            let horizon = 0.5 * (1-tan(5.5 * Double.pi/180)/tan(29 * Double.pi/180))
            let visibleRows = min(target.height,Int(ceil(Double(target.height)*(horizon+0.1))))
            e.setScissorRect(MTLScissorRect(x:0,y:0,width:target.width,height:visibleRows))
        }
        bind(resources, to: e)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        e.endEncoding()
    }

    // Integration smoke test reads actual GPU output, not CPU copies of shader math.
    private func encodeReadbacks(_ command: MTLCommandBuffer, display: MTLTexture) throws -> [Readback] {
        guard let blit = command.makeBlitCommandEncoder() else { throw OceanFailure(message: "Cannot read GPU results") }
        var outputs: [Readback] = []
        var sources: [(String,MTLTexture,Int,Int)] = [("displacement",disp,cascades,0),("slopes",deriv,cascades,0),("moments",moments,cascades,0),("HDR",hdr,1,0),("display",display,1,0)]
        if options["dumpMips"] == "1" {
            for (name,tex) in [("displacement",disp!),("slopes",deriv!),("moments",moments!)] {
                for level in 1..<tex.mipmapLevelCount { sources.append((name+" mip\(level)",tex,cascades,level)) }
            }
            for level in 0..<foam[foamIndex].mipmapLevelCount { sources.append(("foam mip\(level)",foam[foamIndex],2,level)) }
        }
        if options["dumpClouds"] == "1" {
            sources.append(("cached sky",cachedSky,1,0))
            for level in 0..<environment.mipmapLevelCount { sources.append(("environment mip\(level)",environment,6,level)) }
        }
        if options["dumpBloom"] == "1" {
            for (level,texture) in bloom.enumerated() { sources.append(("bloom mip\(level)",texture,1,0)) }
        }
        for (name, tex, layers, level) in sources {
            let w = max(1,tex.width >> level), h = max(1,tex.height >> level)
            let bytesPerPixel = tex.pixelFormat == .bgra8Unorm ? 4 : 8
            let rowBytes = ((w * bytesPerPixel + 255) / 256) * 256
            let imageBytes = rowBytes * h
            let b = try buffer(imageBytes * layers, name + " verification")
            for layer in 0..<layers {
                blit.copy(from: tex, sourceSlice: layer, sourceLevel: level, sourceOrigin: MTLOrigin(x:0,y:0,z:0),
                          sourceSize: MTLSize(width:w,height:h,depth:1), to:b,
                          destinationOffset:layer * imageBytes, destinationBytesPerRow:rowBytes, destinationBytesPerImage:imageBytes)
            }
            outputs.append(Readback(name:name,buffer:b,width:w,height:h,layers:layers,rowBytes:rowBytes,bytesPerPixel:bytesPerPixel))
        }
        if options["dumpClouds"] == "1" {
            let snapshot = try buffer(4,"sun visibility verification")
            blit.copy(from:sunBuffer,sourceOffset:0,to:snapshot,destinationOffset:0,size:4)
            outputs.append(Readback(name:"sun visibility",buffer:snapshot,width:1,height:1,layers:1,rowBytes:4,bytesPerPixel:4))
        }
        if width*2 < height && options["legacyGuard"] != "1" {
            let snapshot = try buffer(16,"guard bounds verification")
            blit.copy(from:displacementBounds,sourceOffset:0,to:snapshot,destinationOffset:0,size:16)
            outputs.append(Readback(name:"guard bounds",buffer:snapshot,width:1,height:1,layers:1,rowBytes:16,bytesPerPixel:16))
        }
        blit.endEncoding()
        return outputs
    }

    private func verify(_ outputs: [Readback]) {
        if let path = options["dump"] {
            for output in outputs where output.name == "HDR" || output.name == "display" {
                var packed = Data()
                for y in 0..<output.height {
                    packed.append(output.buffer.contents().advanced(by:y*output.rowBytes).assumingMemoryBound(to:UInt8.self),count:output.width*output.bytesPerPixel)
                }
                let destination = output.name == "HDR" ? path : path+".bgra8"
                do { try packed.write(to:URL(fileURLWithPath:destination)) }
                catch { record("Cannot write verification capture: \(error)"); exit(1) }
            }
        }
        if let path = options["dump"], options["dumpMips"] == "1" {
            var packed = Data()
            for output in outputs where (output.name.contains(" mip") && !output.name.hasPrefix("environment") && !output.name.hasPrefix("bloom")) || ["displacement","slopes","moments"].contains(output.name) {
                for layer in 0..<output.layers { for y in 0..<output.height {
                    packed.append(output.buffer.contents().advanced(by:layer*output.rowBytes*output.height+y*output.rowBytes).assumingMemoryBound(to:UInt8.self),count:output.width*output.bytesPerPixel)
                } }
            }
            do { try packed.write(to:URL(fileURLWithPath:path+".mips")) }
            catch { record("Cannot write mip capture: \(error)"); exit(1) }
        }
        if let path = options["dump"], options["dumpClouds"] == "1" {
            var packed = Data()
            for output in outputs where output.name == "cached sky" || output.name.hasPrefix("environment") || output.name == "sun visibility" {
                for layer in 0..<output.layers { for y in 0..<output.height {
                    packed.append(output.buffer.contents().advanced(by:layer*output.rowBytes*output.height+y*output.rowBytes).assumingMemoryBound(to:UInt8.self),count:output.width*output.bytesPerPixel)
                } }
            }
            do { try packed.write(to:URL(fileURLWithPath:path+".clouds")) }
            catch { record("Cannot write cloud capture: \(error)"); exit(1) }
        }
        if let path = options["dump"], options["dumpBloom"] == "1" {
            var packed = Data()
            for output in outputs where output.name.hasPrefix("bloom mip") {
                for y in 0..<output.height {
                    packed.append(output.buffer.contents().advanced(by:y*output.rowBytes).assumingMemoryBound(to:UInt8.self),count:output.width*output.bytesPerPixel)
                }
            }
            do { try packed.write(to:URL(fileURLWithPath:path+".bloom")) }
            catch { record("Cannot write bloom capture: \(error)"); exit(1) }
        }
        var observedDisplacementBound = SIMD3<Float>(repeating:0)
        for output in outputs {
            if output.name == "guard bounds" { continue }
            if output.name == "sun visibility" {
                if !output.buffer.contents().assumingMemoryBound(to:Float.self)[0].isFinite { record("Nonfinite sun visibility"); exit(1) }
                continue
            }
            let isDisplacement = output.name == "displacement"
            let data = output.buffer.contents().assumingMemoryBound(to: Float16.self)
            let bytes = output.buffer.contents().assumingMemoryBound(to: UInt8.self)
            for layer in 0..<output.layers {
                var minimum = Float.infinity, maximum = -Float.infinity
                var sum = 0.0
                var layerBound = SIMD3<Float>(repeating:0)
                for y in 0..<output.height { for x in 0..<output.width { for channel in 0..<4 {
                    let offset = layer*output.rowBytes*output.height + y*output.rowBytes + x*output.bytesPerPixel
                    let v = output.bytesPerPixel == 4 ? Float(bytes[offset+channel])/255 : Float(data[offset/2+channel])
                    if !v.isFinite { record("Nonfinite \(output.name) output in layer \(layer)"); exit(1) }
                    if channel<3 {
                        minimum = min(minimum,v); maximum = max(maximum,v); sum += Double(abs(v))
                        if isDisplacement { layerBound[channel] = max(layerBound[channel],abs(v)) }
                    }
                } } }
                if isDisplacement { observedDisplacementBound += layerBound }
                if !output.name.contains(" mip") && (maximum-minimum < 1e-8 || sum == 0) { record("Empty \(output.name) output in layer \(layer)"); exit(1) }
            }
        }
        if let snapshot = outputs.first(where:{$0.name == "guard bounds"}) {
            let bound = snapshot.buffer.contents().assumingMemoryBound(to:Float.self)
            for channel in 0..<3 {
                if !bound[channel].isFinite || bound[channel] < observedDisplacementBound[channel] {
                    record("GPU displacement guard does not bound cascade channel \(channel)"); exit(1)
                }
            }
            verifiedGuardBounds = true
        }
        printDiagnostics()
        if !errors.isEmpty { exit(1) }
        print("PASS: all six wave cascades and HDR/display frames contain finite, nonconstant GPU output.")
        fflush(stdout)
        NSApp.terminate(nil)
    }

    // Benchmark only: exclude time this thread spends descheduled by macOS.
    private func threadCPUTimeMilliseconds() -> Double {
        var stamp = timespec()
        guard clock_gettime(CLOCK_THREAD_CPUTIME_ID,&stamp) == 0 else { return .nan }
        return Double(stamp.tv_sec)*1000+Double(stamp.tv_nsec)/1_000_000
    }

    private func finishBenchmark() {
        guard !benchmarkTimes.isEmpty, errors.isEmpty else { record("Benchmark failed or did not warm up"); exit(1) }
        let times = benchmarkTimes.sorted(), cpu = benchmarkCPUTimes.sorted(), threadCPU = benchmarkThreadCPUTimes.sorted()
        guard threadCPU.count == times.count, threadCPU.allSatisfy({$0.isFinite && $0 > 0}) else { record("Benchmark thread CPU clock failed"); exit(1) }
        let report: [String:Any] = ["device":device.name,"width":width,"height":height,"triangles":triangleCount,"indexBits":indexType == .uint16 ? 16 : 32,"indexBytes":indexBuffer.length,
            "cpuThreadEncodeMedianMs":threadCPU[threadCPU.count/2],"cpuThreadEncodeMeanMs":threadCPU.reduce(0,+)/Double(threadCPU.count),
            "cpuEncodeMedianMs":cpu[cpu.count/2],"cpuEncodeMeanMs":cpu.reduce(0,+)/Double(cpu.count),
            "renderTextureUsage":(([hdr,cachedSky] as [MTLTexture?]).compactMap { $0 }+bloom).map { $0.usage.rawValue },"verifiedResizeLayouts":verifiedResizeLayouts,"batchedBindings":batchBindings,"narrowTextureUsage":options["narrowTextureUsage"] != "0","specializedSkyAAMask":specializedSkyAAMask,"skyAAMask":lastSkyAAMask,"fusedEvolution":fusedEvolution,"spectrumBufferBytes":(specA?.length ?? 0)+(specB?.length ?? 0),"sharedCubic":options["sharedCubic"] != "0","skipCloudOctaves":skipCloudOctaves,"cachedSkyElapsed":cachedSkyElapsed,"clockMode":clock.mode.rawValue,"elapsed":clock.elapsed,"stableDetails":clock.stableDetails,"packedJacobian":packedJacobian,"fusedMips":fusedMipmaps, "mipmapRounding":mipmapRounding.rawValue, "verboseBindings":options["verboseBindings"] == "1", "samples":times.count,"gpuMedianMs":times[times.count/2],"gpuMeanMs":times.reduce(0,+)/Double(times.count),
            "gpuP95Ms":times[min(times.count-1,Int(Double(times.count)*0.95))],
            "gpuStagesMs":profiler?.averageMilliseconds ?? [:],"profiled":profiler != nil,"errors":errors]
        do {
            let data = try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
            if let path = options["report"] { try data.write(to:URL(fileURLWithPath:path)) }
            print(String(data:data,encoding:.utf8)!); fflush(stdout)
        } catch { record("Cannot write benchmark: \(error)"); exit(1) }
        NSApp.terminate(nil)
    }

    private func record(_ message: String) {
        errors.append(message)
        if errors.count > 20 { errors.removeFirst() }
        print("Metal error: \(message)"); fflush(stdout)
    }

    func printDiagnostics() {
        let now = CACurrentMediaTime()
        let fps = Double(frames-diagnosticFrames)/max(0.001,now-diagnosticTime)
        diagnosticFrames = frames; diagnosticTime = now
        let data: [String: Any] = ["physicalGuard":width*2 < height && options["legacyGuard"] != "1","guardBoundsVerified":verifiedGuardBounds,"renderTextureUsage":(([hdr,cachedSky] as [MTLTexture?]).compactMap { $0 }+bloom).map { $0.usage.rawValue },"verifiedResizeLayouts":verifiedResizeLayouts,"batchedBindings":batchBindings,"narrowTextureUsage":options["narrowTextureUsage"] != "0","specializedSkyAAMask":specializedSkyAAMask,"skyAAMask":lastSkyAAMask,"fusedEvolution":fusedEvolution,"spectrumBufferBytes":(specA?.length ?? 0)+(specB?.length ?? 0),"sharedCubic":options["sharedCubic"] != "0","skipCloudOctaves":skipCloudOctaves,"cachedSkyElapsed":cachedSkyElapsed,"clockMode":clock.mode.rawValue,"elapsed":clock.elapsed,"stableDetails":clock.stableDetails,"packedJacobian":packedJacobian,"fusedMips":fusedMipmaps,"mipmapRounding":mipmapRounding.rawValue,"renderer":"Metal", "device":device.name, "fps":(fps*10).rounded()/10,
            "gpuMs":(gpuMilliseconds*100).rounded()/100, "frames":frames, "paused":isPaused,
            "width":width, "height":height, "triangles":triangleCount,"indexBits":indexType == .uint16 ? 16 : 32,"indexBytes":indexBuffer?.length ?? 0, "errors":errors, "gpuStagesMs":profiler?.averageMilliseconds ?? [:]]
        if let encoded = try? JSONSerialization.data(withJSONObject: data, options: .sortedKeys), let text = String(data: encoded, encoding: .utf8) {
            print("Ocean diagnostics: \(text)"); fflush(stdout)
        }
    }
}
