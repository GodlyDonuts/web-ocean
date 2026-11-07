import AppKit
import Darwin
import MetalKit
import simd

private enum Resource {
    case buffer(MTLBuffer), texture(MTLTexture), sampler(MTLSamplerState)
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
    private var rainPipeline:MTLRenderPipelineState!
    private var rainDepthUnoccluded:MTLDepthStencilState!
    private var rainDepth:MTLDepthStencilState!
    private var rainBuffer:MTLBuffer!
    var governor = ""
    var hostLocked=false
    var hostSaverRendering=false
    private(set) var submittedFrames=0
    private(set) var completedFrames=0
    private(set) var presentedDrawables=0
    // Manual hosts bypass MTKView's draw lifecycle, so its cached currentDrawable
    // is not invalidated between callbacks. Acquire a fresh layer drawable instead.
    var usesLayerDrawables=false
    private var skyLUTUpdates=0
    private var tilePresentationVerified=false
    private var benchmarkTileTargets: [MTLTexture]=[]
    private var mirrorPipeline: MTLRenderPipelineState!
    var presentationSurfaces: [MTKView] = []
    var presentationRegions: [ObjectIdentifier:CGRect] = [:]
    // OS-confirmed tile visibility, not CGWindow bounding-box guesses.
    var visibleRegion = RegionalRendering.full
    private var regionalHistory: MTLTexture?
    private var historyPipeline: MTLRenderPipelineState!
    private(set) var shadedFraction = 1.0
    var snapshotRequested: ((Data,Int,Int)->Void)?
    static var resourceBundle: Bundle { Bundle(for:OceanRenderer.self) }

    weak var layoutView: MTKView?
    var pixelBudget: Double = 1280*800
    private var surfaceSizingVerified = false
    var horizonUV: Float { Float(0.5*(1-tan(5.5*Double.pi/180)/tan(29*Double.pi/180))) }
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
    private var verifiedGuardBounds = false
    private var displacementBounds: MTLBuffer!
    private var partialBounds: MTLBuffer!
    private var sunBuffer: MTLBuffer!
    private var lightingTexture: MTLTexture!
    private var cameraWater: MTLBuffer!
    private var skipCloudOctaves = true
    private var packedJacobian = true
    private var useSharedLighting = false
    private var fusedEvolution = true
    private var fusedMipmaps = false
    private var mipmapRounding = MipmapRounding.unsupported
    private var waveMipResources: [[Resource]] = []
    private var foamMipResources: [[[Resource]]] = []
    private var weatherDynamics=WeatherDynamics()
    private(set) var weatherActive=false
    private var weatherManual=false
    private var localWeather:OceanWeather?
    private var weatherTargetDirty=false
    private var weatherSpectrumPrepared=false
    private var lastWeatherSpectrum = -Double.infinity
    private var seaTarget:MTLBuffer!
    private var weatherSimBuffer:MTLBuffer!
    private var seaResponseBuffer:MTLBuffer!
    private var seaSettling=0.0
    private var cloudDrift=SIMD2<Double>.zero
    private var weatherDetailDrift=SIMD2<Double>.zero
    private var cloudEvolutionTime=0.0
    private var fixtureWeatherChanged=false
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
    private var cloudNoise: MTLTexture!
    private var starAtlas: MTLTexture!
    private var galaxyAtlas: MTLTexture!
    private var starCatalogue: MTLBuffer!
    private var starCount=0
    private var starPipeline: MTLRenderPipelineState!
    private var trans: MTLTexture!
    private var multipleScatter: MTLTexture!
    private var skyLUT: MTLTexture!
    private var environment: MTLTexture!
    private var hdr: MTLTexture!
    private var msaa: MTLTexture!
    private var depth: MTLTexture!
    private var offscreenDisplay: MTLTexture?
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
    private var celestialCycle=CelestialCycle()
    private(set) var dayNightEnabled=false
    var onSolarDayChanged: ((SolarDay)->Void)?
    var onLocationMaintenance: (()->Void)?
    private var nextLocationMaintenance: CFTimeInterval=0
    private var cycleAnchor: Date?
    private var cycleStartElapsed=0.0
    private var launchSun=SIMD4<Float>(0,0,0,14)
    private var observerTimeZone: TimeZone?
    private(set) var daylightTime=DaylightTime()
    private var heldLightingDate: Date?
    private var heldLightingDay: Range<Double>?
    private var heldLightingZone: String?
    private var lightingDate: Date?
    var daylightTimeZone: TimeZone { options["timeZone"].flatMap(TimeZone.init(identifier:)) ?? observerTimeZone ?? .autoupdatingCurrent }
    private var celestialState: CelestialState?
    private var lastSolarDayStart: Double?
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
    private var sequenceFrames:Set<Int> {
        Set((options["captureFrames"] ?? "").split(separator:",").compactMap { Int($0) }.filter { $0>=8 && $0<=3600 })
    }
    private var verificationDumpPath:String? {
        options["dump"].map { sequenceFrames.isEmpty ? $0 : $0+String(format:"-%04d",frameIndex) }
    }
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
        self.clock = AnimationClock(start:Double(options["time"] ?? "") ?? 0,mode:AnimationClock.Mode(rawValue:options["clock"] ?? "") ?? .continuous)
        self.time = clock.waveTime
        self.dayNightEnabled = options["dayNight"] == "1" || (!OceanRunMode.offscreen && options["dayNight"] != "0" && options["sunElev"] == nil)
        self.daylightTime=options["daylightTime"].flatMap(DaylightTime.init(value:)) ?? DaylightTime()
        self.celestialCycle = CelestialCycle(cacheURL:OceanRunMode.offscreen ? nil : CelestialCycle.supportDirectory.appendingPathComponent("celestial-days.json"))
        self.celestialCycle.heading = Double(options["heading"] ?? "") .flatMap { $0.isFinite ? $0 : nil } ?? 270
        if let lat=Double(options["latitude"] ?? ""),let lon=Double(options["longitude"] ?? "") {
            let observer=ObserverLocation(latitude:lat,longitude:lon)
            if observer.isValid { self.celestialCycle.location=observer }
        }
        if let utc=Double(options["utc"] ?? ""),utc.isFinite,abs(utc)<1e11 { self.cycleAnchor=Date(timeIntervalSince1970:utc) }
        self.cycleStartElapsed=clock.elapsed
        self.fixedStep = Float(options["fixedDt"] ?? "").flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.cacheUniforms = options["dynamicUniforms"] != "1"
        self.skipCloudOctaves = options["skipCloudOctaves"] != "0"
        self.packedJacobian = options["packedJacobian"] != "0"
        self.useSharedLighting = options["sharedLighting"] == "1" && options["perPixelLighting"] != "1"
        let fixtureWeather=options["weatherValues"].flatMap(OceanWeather.fixture)
        let fixtureStorm=Double(options["storm"] ?? options["weatherFrom"] ?? "").flatMap { $0.isFinite ? OceanWeather.storm($0) : nil }
        if var initial=fixtureWeather ?? fixtureStorm {
            if let heading=Double(options["weatherHeadingFrom"] ?? ""),heading.isFinite,(0...360).contains(heading) { initial.direction=heading }
            self.weatherDynamics=WeatherDynamics(initial);self.weatherActive=true;self.weatherManual=true
            self.cloudEvolutionTime=clock.elapsed
            let a=initial.direction*Double.pi/180
            self.cloudDrift = -SIMD2(cos(a),sin(a))*(initial.wind*0.001*clock.elapsed)
            self.weatherDetailDrift=SIMD2(cos(a),sin(a))*(Double(Float(0.0004))*clock.elapsed)
        }
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
        guard let root = Self.resourceBundle.resourceURL?.appendingPathComponent("Shaders") else {
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
            if source.contains("#include \"WATER_VIEW.metalinc\"") {
                source=source.replacingOccurrences(of:"#include \"WATER_VIEW.metalinc\"",with:try String(contentsOf:root.appendingPathComponent("WATER_VIEW.metalinc"),encoding:.utf8))
            }
            if ["SKY_BG","ENV_CUBE","SUN_VIS"].contains(name) {
                let volume = try String(contentsOf:root.appendingPathComponent("VOLUMETRIC_CLOUDS.metalinc"),encoding:.utf8)
                source = source.replacingOccurrences(of:"// VOLUMETRIC_CLOUD_IMPLEMENTATION",with:volume)
                source = "#define VOLUMETRIC_CLOUDS \(options["volumetricClouds"] == "0" ? 0 : 1)\n"+source
            }
            if ["SKY_BG","ENV_CUBE","SUN_VIS","OCEAN"].contains(name) {
                let celestial = try String(contentsOf:root.appendingPathComponent("CELESTIAL_SKY.metalinc"),encoding:.utf8)
                source=source.replacingOccurrences(of:"// CELESTIAL_SKY_IMPLEMENTATION",with:try String(contentsOf:root.appendingPathComponent("STELLAR_POINTS.metalinc"),encoding:.utf8)+celestial)
            }
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
                    case "SIM_INIT", "SIM_EVOLVE", "WEATHER_SEA": threads = MTLSize(width: 16, height: 16, depth: 1)
                    case "SIM_MIPS_FUSED4", "ARRAY16_MIPS_FUSED4": threads = MTLSize(width:8,height:8,depth:1)
                    case "ARRAY16_MIPS_FUSED5": threads = MTLSize(width:16,height:16,depth:1)
                    case "LIGHTING", "CAMERA_WATER": threads = MTLSize(width: 1, height: 1, depth: 1)
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
        starPipeline = try renderPipeline("STARS", samples:4,depth:true,additive:true)
        cachePipeline = try renderPipeline("SKY_BG")
        if specializedSkyAAMask != 3 {
            prunedCachePipeline = try renderPipeline("SKY_BG_PRUNED")
            prunedStableCachePipeline = try renderPipeline("SKY_BG_PRUNED_STABLE")
        }
        downPipeline = try renderPipeline("BLOOM_DOWN")
        upPipeline = try renderPipeline("BLOOM_UP", additive: true)
        rainPipeline=try renderPipeline("RAIN",samples:4,depth:true,premultiplied:true)
        compositePipeline = try renderPipeline("COMPOSITE", format: .bgra8Unorm)
        let mirror = MTLRenderPipelineDescriptor()
        mirror.label = "COMPOSITE mirror"
        mirror.vertexFunction = libraries["COMPOSITE"]!.makeFunction(name: "vs")
        mirror.fragmentFunction = libraries["COMPOSITE"]!.makeFunction(name: "fs_mirror")
        mirror.colorAttachments[0].pixelFormat = .bgra8Unorm
        mirrorPipeline = try device.makeRenderPipelineState(descriptor: mirror)
        let historyLibrary=try device.makeLibrary(source:"""
        #include <metal_stdlib>
        using namespace metal;
        vertex float4 historyVS(uint i [[vertex_id]]) { return float4(float2((i<<1)&2,i&2)*2-1,0,1); }
        fragment float4 historyFS(float4 p [[position]],texture2d<float> t [[texture(0)]]) { return t.read(uint2(p.xy)); }
        """,options:nil)
        let historyDescriptor=MTLRenderPipelineDescriptor()
        historyDescriptor.vertexFunction=historyLibrary.makeFunction(name:"historyVS")
        historyDescriptor.fragmentFunction=historyLibrary.makeFunction(name:"historyFS")
        historyDescriptor.colorAttachments[0].pixelFormat = .rgba16Float
        historyDescriptor.depthAttachmentPixelFormat = .depth32Float
        historyDescriptor.rasterSampleCount=4
        historyPipeline=try device.makeRenderPipelineState(descriptor:historyDescriptor)
        let d = MTLDepthStencilDescriptor()
        d.depthCompareFunction = .greater; d.isDepthWriteEnabled = true
        oceanDepth = device.makeDepthStencilState(descriptor: d)
        d.depthCompareFunction = .equal; d.isDepthWriteEnabled = false
        skyDepth = device.makeDepthStencilState(descriptor: d)
        d.depthCompareFunction = .greater;d.isDepthWriteEnabled=false;rainDepth=device.makeDepthStencilState(descriptor:d)
        d.depthCompareFunction = .always;rainDepthUnoccluded=device.makeDepthStencilState(descriptor:d)
    }

    private func renderPipeline(_ name: String, samples: Int = 1, depth: Bool = false,
                                additive: Bool = false, premultiplied:Bool=false, format: MTLPixelFormat = .rgba16Float) throws -> MTLRenderPipelineState {
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
        if premultiplied {
            let c=d.colorAttachments[0]!
            c.isBlendingEnabled=true;c.sourceRGBBlendFactor = .one;c.destinationRGBBlendFactor = .oneMinusSourceAlpha
            c.sourceAlphaBlendFactor = .one;c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
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
        cloudNoise = try CloudNoise.make(device:device)
        galaxyAtlas=try GalaxyAtlas.make(device:device,queue:queue,enabled:dayNightEnabled)
        let stars=try StarField.make(device:device,queue:queue,enabled:dayNightEnabled,atlasSize:options["starAtlasReference"] == "1" ? 2048 : 1024)
        starAtlas=stars.atlas;starCatalogue=stars.catalogue;starCount=stars.count
        frameBuffer = try buffer(576+AnimationClock.cloudShiftCount*16, "frame")
        displacementBounds = try buffer(16,"displacement guard bounds")
        partialBounds = try buffer(16*16*cascades*16,"partial displacement bounds",privateStorage:true)
        simBuffer = try buffer(224, "spectrum parameters")
        foamBuffer = try buffer(144, "foam parameters")
        atmoBuffer = try buffer(16, "atmosphere parameters")
        rainBuffer=try buffer(64,"world rain advection")
        compositeBuffer = try buffer(64, "tone mapping and precipitation")
        sizesBuffer = try buffer(128, "shader buffer sizes")
        // Runtime arrays have explicit, CPU-validated indices. This metadata is
        // retained by the migrated Metal function signatures, but is not read.
        memset(sizesBuffer.contents(), 0, sizesBuffer.length)
        sunBuffer = try buffer(16, "sun visibility", privateStorage: true)
        cameraWater = try buffer(16,"camera water state",privateStorage:true)
        lightingTexture = try texture(5,1,"shared ocean lighting",format:.rgba32Float)
        let bytes = n * n * cascades * 16
        h0 = try buffer(bytes, "initial spectrum", privateStorage: true)
        // Allocate the second sea state only for local/manual weather, not
        // legacy offscreen reference captures.
        if !OceanRunMode.offscreen || weatherManual {
            seaTarget=try buffer(bytes,"weather target spectrum",privateStorage:true)
            weatherSimBuffer=try buffer(224,"weather target parameters")
            seaResponseBuffer=try buffer(16,"sea relaxation")
        }
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
        bloomUniforms = try (0..<bloomLevels*2).map { try buffer(16, "bloom uniform \($0)") }
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
        f[17] = verificationEnabled ? min(10,max(0.1,value("testEyeHeight",2.4))) : 2.4; f[19] = clock.detailTime
        f[20] = tanX; f[23] = Float(envFace)
        f[25] = up.y * tanY; f[26] = up.z * tanY
        f[29] = forward.y; f[30] = forward.z
        let elevation = value("sunElev", 2.6) * d2r, azimuth = value("sunAzim", 4) * d2r
        f[32] = sin(azimuth)*cos(elevation); f[33] = sin(elevation); f[34] = -cos(azimuth)*cos(elevation); f[35] = 14
        launchSun=SIMD4(f[32],f[33],f[34],f[35])
        f[36] = Float(width); f[37] = Float(height); f[38] = 1/Float(width); f[39] = 1/Float(height)
        for c in 0..<cascades { f[40+c] = cascadeLengths[c]; f[48+c] = 1/cascadeLengths[c] }
        let wind = weatherActive ? Float(weatherDynamics.current.wind) : value("windSpeed", 7), windDirection = (weatherActive ? Float(weatherDynamics.current.direction) : value("windDir", 118)) * d2r
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
        // Remote swell is independent of the user's local rain and wind. This
        // is an idealized offshore background, not a marine forecast.
        s[44] = max(0,value("swellHs",1.8)); s[45] = 94*d2r
        s[46] = 2 * .pi / min(25,max(4,value("swellPeriod",11))); s[47] = 48
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
        // Cloud evolution follows the same accelerated preview timeline as
        // astronomy, but uses bounded texture phases at ordinary wall speed.
        let rate=Double(options["cycleRate"] ?? "").flatMap { $0.isFinite && $0>0 && $0<=86400 ? $0 : nil } ?? 1
        let baseTime = clock.mode == .continuous ? clock.elapsed : Double(clock.detailTime)
        let cloudTime = cycleAnchor == nil ? baseTime : cycleStartElapsed+(baseTime-cycleStartElapsed)*rate
        let windSpeed = (weatherActive ? weatherDynamics.current.wind : Double(max(0,value("windSpeed",7))))*0.001
        let windAngle = (weatherActive ? weatherDynamics.current.direction : Double(value("windDir",118)))*Double.pi/180
        let velocity = SIMD2(cos(windAngle),sin(windAngle))*windSpeed
        let cloudPhases: [Float]
        if weatherActive {
            // Integrate velocity: changing wind never teleports the noise field.
            let drift = cloudDrift
            cloudPhases=[AnimationClock.fraction(drift.x*0.09),AnimationClock.fraction(drift.y*0.09),
                AnimationClock.fraction(drift.x*0.018),AnimationClock.fraction(drift.y*0.018),
                AnimationClock.fraction(cloudEvolutionTime*0.000041),AnimationClock.fraction(-cloudEvolutionTime*0.000027),
                AnimationClock.fraction(drift.x*0.022*1.4),AnimationClock.fraction(drift.y*0.009*1.4)]
        } else { cloudPhases=AnimationClock.volumetricCloudPhases(time:cloudTime,velocity:velocity) }
        for i in 0..<4 { frame[152+i]=cloudPhases[i];frame[184+i]=cloudPhases[4+i] }
        guard clock.stableDetails || weatherActive else { frame[63] = 0; return }
        let phases = weatherActive ? SIMD4(AnimationClock.fraction(weatherDetailDrift.x),AnimationClock.fraction(weatherDetailDrift.y),AnimationClock.fraction(cloudEvolutionTime*Double(Float(0.013))),1) : clock.detailPhases(wind:SIMD2(frame[56],frame[57]))
        for i in 0..<4 { frame[60+i] = phases[i] }
        if updateClouds {
            clock.writeCloudShifts(to:UnsafeMutableBufferPointer(start:frameBuffer.contents().advanced(by:384).assumingMemoryBound(to:UInt32.self),count:AnimationClock.cloudShiftCount*4))
        }
    }

    func setLocalWeather(_ value:OceanWeather) {
        guard value.isValid else { return }
        var adjusted=value
        adjusted.direction=(value.direction+270-celestialCycle.heading+720).truncatingRemainder(dividingBy:360)
        localWeather=adjusted
        if !weatherManual { setWeather(adjusted) }
    }
    func followLocalWeather() { weatherManual=false;if let value=localWeather { setWeather(value) } }
    func previewStorm(_ value:Double) { weatherManual=true;setWeather(.storm(value)) }
    private func setWeather(_ value:OceanWeather) {
        guard value.isValid,value != weatherDynamics.target else { return }
        if !weatherActive {
            cloudEvolutionTime=clock.elapsed
            let a=Double(self.value("windDir",118))*Double.pi/180
            cloudDrift = -SIMD2(cos(a),sin(a))*(Double(self.value("windSpeed",7))*0.001*clock.elapsed)
            weatherDetailDrift=SIMD2(cos(a),sin(a))*(Double(Float(0.0004))*clock.elapsed)
        }
        weatherTargetDirty = weatherTargetDirty || !value.hasSameWind(as:weatherDynamics.target)
        weatherActive=true;weatherDynamics.setTarget(value)
    }
    private func updateWeather(dt:Double) {
        if let to=Double(options["weatherTo"] ?? ""),!fixtureWeatherChanged,
           clock.elapsed-cycleStartElapsed >= (Double(options["weatherChangeAt"] ?? "") ?? 1) {
            fixtureWeatherChanged=true
            var target=OceanWeather.storm(to)
            if let heading=Double(options["weatherHeadingTo"] ?? ""),heading.isFinite,(0...360).contains(heading) { target.direction=heading }
            setWeather(target)
        }
        guard weatherActive else { return }
        weatherDynamics.advance(dt)
        let w=weatherDynamics.current
        let angle=w.direction*Double.pi/180
        cloudDrift -= SIMD2(cos(angle),sin(angle))*(w.wind*0.001*dt)
        weatherDetailDrift += SIMD2(cos(angle),sin(angle))*(Double(Float(0.0004))*dt)
        cloudEvolutionTime += dt
        seaSettling=max(0,seaSettling-dt)
    }
    private func writeWeatherUniforms(dt:Double) {
        defer { writeCloudMorphology() }
        let frame=frameBuffer.contents().assumingMemoryBound(to:Float.self)
        let post=compositeBuffer.contents().assumingMemoryBound(to:Float.self)
        for i in 8..<16 { post[i]=0 }
        for i in 188..<192 { frame[i]=0 }
        memset(rainBuffer.contents(),0,64)
        guard weatherActive else { return }
        let w=weatherDynamics.current,severity=w.severity,seaSeverity=w.windSeaSeverity
        let formation=max(0,min(1,(w.cloud-0.45)/0.5))
        let growth=severity*formation*formation*(3-2*formation)
        let canopy=max(0,min(1,(w.cloud-0.55)/0.38))
        let heavy=max(0,min(1,(w.rain-0.15)/0.45))
        let rain=w.rain*((1-heavy)+heavy*canopy*canopy*(3-2*canopy))
        frame[56]=Float(cos(w.direction*Double.pi/180));frame[57]=Float(sin(w.direction*Double.pi/180));frame[58]=Float(w.wind)
        frame[93]=Float(w.cloud);frame[94]=Float(2.2+severity*2.0)
        frame[74]=Float(max(Double(value("veil",0.36)),w.cloud*0.8))
        frame[84]=0.36+0.12*value("foam",1)+Float(seaSeverity*0.42)
        // Dense marine rain/fog fades the horizon in world distance.
        let fog=Float(w.mist)*0.0025
        frame[88]=(5.802e-3+4.40e-3*value("haze",3))*1e-3+fog
        frame[89]=(13.558e-3+4.40e-3*value("haze",3))*1e-3+fog
        frame[90]=(33.1e-3+4.40e-3*value("haze",3))*1e-3+fog
        frame[188]=Float(severity);frame[189]=Float(rain);frame[190]=Float(w.mist);frame[191]=Float(growth)
        // Exposure/light response is continuous; the cloud march supplies the
        // directional occlusion, including the ocean reflection environment.
        let dim=Float(1-severity*0.60)
        frame[35] *= dim;frame[167] *= dim
        post[8]=Float(rain);post[9]=Float(cos(w.direction*Double.pi/180)*w.wind/45)
        post[10]=Float(cloudEvolutionTime.truncatingRemainder(dividingBy:53248));post[11]=Float(w.mist)
        post[12]=Float(severity);post[13]=Float(w.thunder)
        post[14]=Float(celestialState?.night ?? 0)
        post[15]=Float(WeatherLightning.flash(time:cloudEvolutionTime,thunder:w.thunder))
        let particles=rainBuffer.contents().assumingMemoryBound(to:Float.self)
        particles[0]=AnimationClock.fraction(-cloudDrift.x*1000*0.5/200)*200
        particles[1]=AnimationClock.fraction(-cloudDrift.y*1000*0.5/200)*200
        particles[2]=Float(cos(w.direction*Double.pi/180)*w.wind*0.5)
        particles[3]=Float(sin(w.direction*Double.pi/180)*w.wind*0.5)
        for bucket in 0..<8 { particles[4+bucket]=AnimationClock.fraction(cloudEvolutionTime*Double(20+bucket)/64)*64 }
        particles[12]=post[15];particles[13]=Float(rain)
        let foam=foamBuffer.contents().assumingMemoryBound(to:Float.self)
        foam[11]=Float(0.22+seaSeverity*0.45);foam[12]=0.52+0.16*value("foam",1)-Float(seaSeverity*0.28)
        foam[32]=frame[56]*Float(w.wind)*0.03;foam[33]=frame[57]*Float(w.wind)*0.03
        if let seaResponseBuffer {
            write([Float(1-exp(-dt/90)),0,0,0],to:seaResponseBuffer)
        }
    }
    private func writeCloudMorphology() {
        let f=frameBuffer.contents().assumingMemoryBound(to:Float.self)
        let kind=CloudMorphology.Kind(rawValue:options["cloudType"] ?? "auto") ?? .automatic
        let w=weatherActive ? weatherDynamics.current : OceanWeather(rain:0,cloud:Double(f[93]),wind:Double(f[58]),direction:118,thunder:0,mist:0)
        if let coverage=CloudMorphology.coverage(kind) { f[93]=coverage.low;f[74]=coverage.high }
        if kind == .cumulonimbus { f[191]=1 }
        frameBuffer.contents().assumingMemoryBound(to:SIMD4<Float>.self)[49]=CloudMorphology.weights(w,kind:kind)
    }
    private func prepareWeatherSpectrum() {
        weatherSpectrumPrepared=false
        guard weatherTargetDirty,let weatherSimBuffer,clock.elapsed-lastWeatherSpectrum>=1 else { return }
        weatherSpectrumPrepared=true
        memcpy(weatherSimBuffer.contents(),simBuffer.contents(),224)
        let p=weatherSimBuffer.contents().assumingMemoryBound(to:Float.self)
        let w=weatherDynamics.target
        p[40]=Float(max(0.2,w.wind));p[41]=Float(w.direction*Double.pi/180)
        // Retain independent swell height/period and the same JONSWAP peak
        // shape as startup. Only local wind speed/direction retarget wind sea.
        seaSettling=900
    }

    func setObserverLocation(_ location: ObserverLocation?, timeZone: TimeZone? = nil) {
        guard celestialCycle.location != location || observerTimeZone != timeZone else { return }
        observerTimeZone=timeZone;heldLightingDay=nil
        celestialCycle.location=location;lastSolarDayStart=nil;cacheDirty=true
    }
    func setDaylightTime(_ selection: DaylightTime) {
        guard daylightTime != selection else { return }
        daylightTime=selection;heldLightingDate=nil;heldLightingDay=nil;cacheDirty=true
    }
    private func selectedLightingDate(reference: Date, zone: TimeZone) -> Date {
        guard daylightTime.mode != .automatic else { return reference }
        if heldLightingDay?.contains(reference.timeIntervalSince1970) != true || heldLightingZone != zone.identifier {
            _=celestialCycle.state(at:reference,zone:zone)
            if let day=celestialCycle.day {
                heldLightingDate=daylightTime.date(reference:reference,day:day,zone:zone)
                heldLightingDay=day.start..<day.end;heldLightingZone=zone.identifier;cacheDirty=true
            }
        }
        return heldLightingDate ?? reference
    }
    private func daylightDiagnostics() -> [String:Any] {
        ["daylightTime":daylightTime.value,"daylightHeld":daylightTime.mode != .automatic && heldLightingDate != nil,
         "lightingUTC":lightingDate.map { $0.timeIntervalSince1970 as Any } ?? NSNull()]
    }
    private func writeCelestialUniforms() {
        let frame=frameBuffer.contents().assumingMemoryBound(to:Float.self)
        let staticSun=launchSun
        celestialState=nil
        lightingDate=nil
        frame[32]=staticSun.x;frame[33]=staticSun.y;frame[34]=staticSun.z;frame[35]=staticSun.w
        compositeBuffer.contents().assumingMemoryBound(to:Float.self)[0]=value("exposure",1.35)
        compositeBuffer.contents().assumingMemoryBound(to:Float.self)[7]=0
        let vectors=frameBuffer.contents().assumingMemoryBound(to:SIMD4<Float>.self)
        vectors[39]=SIMD4(0,-1,0,0)
        vectors[40]=SIMD4(0.004675,0.0045,0,0)
        vectors[41]=staticSun;vectors[42]=SIMD4(staticSun.x,staticSun.y,staticSun.z,0.004675)
        vectors[43]=SIMD4(1,0,0,0);vectors[44]=SIMD4(0,1,0,0);vectors[45]=SIMD4(0,0,1,0)
        vectors[48]=staticSun
        guard dayNightEnabled else { return }
        let rate=Double(options["cycleRate"] ?? "").flatMap { $0.isFinite && $0>0 && $0<=86400 ? $0 : nil } ?? 1
        let reference=cycleAnchor.map { $0.addingTimeInterval((clock.elapsed-cycleStartElapsed)*rate) } ?? Date()
        let zone=daylightTimeZone
        let date=selectedLightingDate(reference:reference,zone:zone)
        guard let state=celestialCycle.state(at:date,zone:zone) else { return }
        lightingDate=date
        celestialState=state
        let astronomical=options["celestialPath"] == "astronomical"
        let bodies=astronomical ? nil : celestialCycle.wallpaperBodies(at:date,zone:zone,horizontalTangent:Double(frame[20]))
        let sun=bodies?.sun ?? state.sun
        let apparentSun=bodies?.sun ?? state.apparentSun
        let moon = astronomical || options["moonPath"] == "astronomical" ? state.moon : bodies?.moon ?? state.moon
        let phaseLight=WallpaperSky.phaseLight(state:state,displayedMoon:moon)
        vectors[48]=SIMD4(Float(phaseLight.x),Float(phaseLight.y),Float(phaseLight.z),0)
        for i in 0..<3 {
            let axis=state.skyBasis[i];vectors[43+i]=SIMD4(Float(axis.x),Float(axis.y),Float(axis.z),0)
        }
        vectors[8]=SIMD4(Float(sun.x),Float(sun.y),Float(sun.z),14)
        vectors[39]=SIMD4(Float(moon.x),Float(moon.y),Float(moon.z),Float(state.moonIllumination))
        vectors[40]=SIMD4(Float(state.sunRadius),Float(state.moonRadius),Float(state.night),1)
        vectors[42]=SIMD4(Float(apparentSun.x),Float(apparentSun.y),Float(apparentSun.z),Float(state.sunRadius))
        if state.sunAltitude > -1 {
            vectors[41]=SIMD4(Float(apparentSun.x),Float(apparentSun.y),Float(apparentSun.z),14)
        } else {
            // Photographic lunar key: real phase and the displayed horizon gate the
            // source. Strong specular light against restrained sky fill gives
            // a broken silver path instead of a uniformly blue sea.
            let brightness=0.35*pow(state.moonIllumination,1.5)*state.night*CelestialMath.smooth(-0.01,0.08,moon.y)
            vectors[41]=SIMD4(Float(moon.x),Float(moon.y),Float(moon.z),Float(brightness))
        }
        compositeBuffer.contents().assumingMemoryBound(to:Float.self)[0]=value("exposure",1.35)*Float(1+3*state.night)
        // Daytime contrast fades out before golden hour; keep the established
        // sunset and lunar treatment. q.w was reserved in the existing buffer.
        compositeBuffer.contents().assumingMemoryBound(to:Float.self)[7]=Float(CelestialMath.smooth(0.08,0.30,sun.y)*(1-state.night))
        if let day=celestialCycle.day,lastSolarDayStart != day.start {
            lastSolarDayStart=day.start;onSolarDayChanged?(day)
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

    private func groups(_ w: Int, _ h: Int, _ layers: Int = 1) -> MTLSize { MTLSize(width: (w+7)/8, height: (h+7)/8, depth: layers) }
    private func mip(_ name: String, _ level: Int) -> MTLTexture { mipViews[name]![level] }

    private func updateSize(_ view: MTKView) throws {
        let layout: ViewportLayout
        if (verificationEnabled || benchmarkEnabled),
           let testWidth = Double(options["renderWidth"] ?? ""), let testHeight = Double(options["renderHeight"] ?? "") {
            // Verification can exercise real portrait/ultrawide GPU targets even
            // when AppKit constrains the test window to the attached display.
            layout = ViewportLayout(pointWidth:testWidth,pointHeight:testHeight,backingScale:1)
        } else {
            layout = ViewportLayout(pointWidth:Double(view.bounds.width),pointHeight:Double(view.bounds.height),
                                    backingScale:Double(view.window?.backingScaleFactor ?? 2),pixelBudget:pixelBudget)
        }
        let w = layout.width, h = layout.height
        // A replacement MTKView still needs sizing even when shared resources
        // already have the right dimensions (display mode changes/hot-plug).
        let drawableSize = CGSize(width:w,height:h)
        if view.drawableSize != drawableSize { view.drawableSize = drawableSize }
        guard w != width || h != height else { return }
        if indexBuffer == nil || columns != layout.columns || rows != layout.rows {
            columns = layout.columns; rows = layout.rows
            try createGrid()
        }
        width = w; height = h
        uniformsDirty = true
        offscreenDisplay=nil;benchmarkTileTargets=[]
        if OceanRunMode.offscreen {
            offscreenDisplay = try texture(w,h,"offscreen display",format:.bgra8Unorm,renderOnly:true)
        }
        hdr = try texture(w, h, "HDR scene", renderOnly: true)
        regionalHistory=nil
        msaa = try texture(w, h, "transient MSAA", samples: 4, transient: true)
        depth = try texture(w, h, "transient depth", format: .depth32Float, samples: 4, transient: true)
        cachedSky = try texture(max(1,w/2), max(1,h/2), "cached sky", renderOnly: true)
        bloom = try (0..<bloomLevels).map { try texture(max(1,w >> ($0+1)), max(1,h >> ($0+1)), "bloom \($0)", renderOnly: true) }
        for i in 0..<bloomLevels {
            let sourceW = i == 0 ? w : bloom[i-1].width, sourceH = i == 0 ? h : bloom[i-1].height
            write([1/Float(sourceW),1/Float(sourceH),i == 0 ? 1 : 0,0], to: bloomUniforms[i])
            write([1/Float(bloom[i].width),1/Float(bloom[i].height),1,1], to: bloomUniforms[bloomLevels+i])
        }
        cacheDirty = true
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { cacheDirty = true }

    func draw(in view: MTKView) {
        let snapshotOnly=isPaused && snapshotRequested != nil
        guard (!isPaused || snapshotOnly), gate.wait(timeout: .now()) == .success else { return }
        var committed = false
        defer { if !committed { gate.signal() } }
        do { try updateSize(layoutView ?? view) } catch { record(error.localizedDescription); return }
        let drawable: CAMetalDrawable?
        var display: MTLTexture
        var acquiredRegions: [CGRect]=[]
        var surfaceDrawables: [CAMetalDrawable] = []
        if OceanRunMode.offscreen || snapshotOnly {
            drawable = nil
            if offscreenDisplay == nil {
                do { offscreenDisplay=try texture(width,height,"snapshot display",format:.bgra8Unorm,renderOnly:true) }
                catch { record(error.localizedDescription); return }
            }
            guard let target = offscreenDisplay else { return }
            display = target
        } else if !presentationSurfaces.isEmpty {
            drawable = nil
            for surface in presentationSurfaces {
                if let region=presentationRegions[ObjectIdentifier(surface)],let layer=surface.layer as? CAMetalLayer {
                    let visible=RegionalRendering.output(region,width:width,height:height)
                    let rect=RegionalRendering.tileCrop(region,width:width,height:height)
                    let size=rect.size
                    // Paused secondary MTKViews don't run their draw/layout path.
                    // Synchronize the actual layer before raw drawable acquisition.
                    if surface.drawableSize != size { surface.drawableSize=size }
                    if layer.drawableSize != size { layer.drawableSize=size }
                    layer.framebufferOnly=false
                    layer.contentsRect=CGRect(x:(visible.minX-rect.minX)/rect.width,y:0,width:visible.width/rect.width,height:1)
                }
                let next = surface === view && !usesLayerDrawables
                    ? surface.currentDrawable : (surface.layer as? CAMetalLayer)?.nextDrawable()
                if let next {
                    surfaceDrawables.append(next)
                    if let region=presentationRegions[ObjectIdentifier(surface)] { acquiredRegions.append(region) }
                }
            }
            guard let first = surfaceDrawables.first else { return }
            if !presentationRegions.isEmpty {
                if offscreenDisplay == nil {
                    do { offscreenDisplay=try texture(width,height,"shared tile display",format:.bgra8Unorm,renderOnly:true) }
                    catch { record(error.localizedDescription);return }
                }
                display=offscreenDisplay!
            } else { display = first.texture }
        } else {
            guard let next = usesLayerDrawables ? (view.layer as? CAMetalLayer)?.nextDrawable() : view.currentDrawable else { return }
            drawable = next
            display = next.texture
        }
        if verificationEnabled && options["testSurfaceSizing"] == "1" && !surfaceSizingVerified {
            do { try verifySurfaceSizing() } catch { record(error.localizedDescription); return }
        }
        let descriptor = MTLCommandBufferDescriptor()
        if diagnostics { descriptor.errorOptions = .encoderExecutionStatus }
        guard let command = queue.makeCommandBuffer(descriptor: descriptor) else { record("Cannot allocate command buffer"); return }
        command.label = "Ocean frame \(frameIndex)"
        let now = CACurrentMediaTime()
        let cpuThreadStart = benchmarkEnabled ? threadCPUTimeMilliseconds() : 0
        let elapsedStep = fixedStep.map(Double.init) ?? (lastTime == 0 ? 1.0/30 : min(0.1,now-lastTime))
        let dt = Float(elapsedStep)
        if let maintenance=onLocationMaintenance,now>=nextLocationMaintenance {
            nextLocationMaintenance=now+60;maintenance()
        }
        lastTime = now; clock.advance(by:elapsedStep); time = clock.waveTime; frameIndex += 1
        let cadence = fixedStep == nil ? now : Double(frameIndex)*Double(dt)
        let weatherRate=cycleAnchor == nil ? 1 : (Double(options["cycleRate"] ?? "").flatMap { $0.isFinite && $0>0 && $0<=86400 ? $0 : nil } ?? 1)
        let weatherStep=elapsedStep*weatherRate
        updateWeather(dt:weatherStep)
        writeUniforms(dt: dt)
        writeTemporalUniforms(updateClouds:!initialized || cacheDirty || cadence-lastCache >= 0.125 || cadence-lastEnvironment >= 0.1 || cadence-lastSky >= 0.25)
        writeCelestialUniforms()
        writeWeatherUniforms(dt:weatherStep)
        prepareWeatherSpectrum()
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
        if let seaTarget {
            if !initialized || weatherSpectrumPrepared {
                dispatch("SIM_INIT",c,[.buffer(weatherSpectrumPrepared ? weatherSimBuffer : simBuffer),.buffer(seaTarget)],groups:MTLSize(width:n/16,height:n/16,depth:cascades))
                if weatherSpectrumPrepared { weatherTargetDirty=false;lastWeatherSpectrum=clock.elapsed }
            }
            if weatherActive && seaSettling>0 {
                dispatch("WEATHER_SEA",c,[.buffer(h0),.buffer(seaTarget),.buffer(seaResponseBuffer)],groups:MTLSize(width:n/16,height:n/16,depth:cascades))
            }
        }
        if fusedEvolution {
            dispatch("SIM_EVOLVE_ROWS",c,[.buffer(simBuffer),.buffer(h0),.buffer(tmpA),.buffer(tmpB)],groups:MTLSize(width:n,height:1,depth:cascades))
        } else {
            dispatch("SIM_EVOLVE", c, [.buffer(simBuffer),.buffer(h0),.buffer(specA),.buffer(specB)], groups: MTLSize(width:n/16,height:n/16,depth:cascades))
            dispatch("FFT_ROWS", c, [.buffer(specA),.buffer(specB),.buffer(tmpA),.buffer(tmpB)], groups: MTLSize(width:n,height:1,depth:cascades))
        }
        dispatch("FFT_COLS", c, [.buffer(tmpA),.buffer(tmpB),.texture(mip("disp",0)),.texture(mip("deriv",0)),.texture(mip("moments",0))], groups: MTLSize(width:n,height:1,depth:cascades))
        if fusedMipmaps {
            for (index,base) in [0,4].enumerated() {
                dispatch("SIM_MIPS_FUSED4",c,waveMipResources[index],groups:MTLSize(width:max(1,n>>(base+4)),height:max(1,n>>(base+4)),depth:cascades))
            }
        } else {
            for m in 1..<9 {
                dispatch("SIM_MIPS",c,[.texture(mip("disp",m-1)),.texture(mip("deriv",m-1)),.texture(mip("moments",m-1)),.texture(mip("disp",m)),.texture(mip("deriv",m)),.texture(mip("moments",m))],groups:groups(max(1,n>>m),max(1,n>>m),cascades))
            }
        }
        if width*2 < height && options["legacyGuard"] != "1" {
            dispatch("DISPLACEMENT_BOUNDS",c,[.texture(mip("disp",0)),.buffer(partialBounds)],groups:MTLSize(width:16,height:16,depth:cascades))
            dispatch("DISPLACEMENT_BOUNDS_FINAL",c,[.buffer(partialBounds),.buffer(displacementBounds)],groups:MTLSize(width:1,height:1,depth:1))
        }
        if profiler != nil {
            c.endEncoding()
            guard let next = makeCompute(command,label:"foam") else { return }
            c = next
        }
        foamIndex = 1-foamIndex
        dispatch("FOAM_UPDATE", c, [.buffer(foamBuffer),.texture(mip("foam\(1-foamIndex)",0)),.texture(mip("foam\(foamIndex)",0)),.texture(disp),.texture(deriv),.sampler(simSampler),.sampler(simSampler)], groups: groups(foamSize,foamSize,2))
        if fusedMipmaps {
            dispatch("ARRAY16_MIPS_FUSED4",c,foamMipResources[foamIndex][0],groups:MTLSize(width:foamSize/16,height:foamSize/16,depth:2))
            dispatch("ARRAY16_MIPS_FUSED5",c,foamMipResources[foamIndex][1],groups:MTLSize(width:1,height:1,depth:2))
        } else {
            for m in 1..<10 { dispatch("ARRAY16_MIPS",c,[.texture(mip("foam\(foamIndex)",m-1)),.texture(mip("foam\(foamIndex)",m))],groups:groups(max(1,foamSize>>m),max(1,foamSize>>m),2)) }
        }
        dispatch("CAMERA_WATER",c,[.buffer(frameBuffer),.texture(disp),.sampler(repeatSampler),.buffer(cameraWater)],groups:MTLSize(width:1,height:1,depth:1))
        let lightingChanged = !initialized || cadence-lastSky >= 0.25 || cadence-lastEnvironment >= 0.1
        if !initialized || cadence-lastSky >= 0.25 {
            if profiler != nil {
                c.endEncoding()
                guard let next = makeCompute(command,label:"atmosphere") else { return }
                c = next
            }
            dispatch("SKYVIEW_LUT", c, [.buffer(frameBuffer),.texture(trans),.texture(multipleScatter),.sampler(clampSampler),.texture(skyLUT)], groups: groups(256,144))
            skyLUTUpdates += 1
            dispatch(clock.stableDetails ? "SUN_VIS_STABLE" : "SUN_VIS", c, [.buffer(frameBuffer),.texture(trans),.texture(skyLUT),.sampler(clampSampler),.buffer(sunBuffer),.texture(cloudNoise),.texture(starAtlas),.texture(galaxyAtlas)], groups: MTLSize(width:1,height:1,depth:1))
            lastSky = cadence
        }
        if !initialized || cadence-lastEnvironment >= 0.1 {
            if profiler != nil {
                c.endEncoding()
                guard let next = makeCompute(command,label:"environment") else { return }
                c = next
            }
            let faces = initialized ? 1 : 6
            dispatch(clock.stableDetails ? "ENV_CUBE_STABLE" : "ENV_CUBE", c, [.buffer(frameBuffer),.texture(trans),.texture(skyLUT),.sampler(clampSampler),.texture(mip("env",0)),.texture(cloudNoise),.texture(starAtlas),.texture(galaxyAtlas)], groups: groups(128,128,faces))
            for m in 1..<8 { dispatch("CUBE_MIPS", c, [.texture(mip("env",m-1)),.texture(mip("env",m)),.buffer(frameBuffer)], groups: groups(max(1,128>>m),max(1,128>>m),faces)) }
            envFace = (envFace+1)%6; lastEnvironment = cadence
        }
        if useSharedLighting && lightingChanged {
            if profiler != nil {
                c.endEncoding()
                guard let next = makeCompute(command,label:"shared lighting") else { return }
                c = next
            }
            dispatch("LIGHTING",c,[.buffer(frameBuffer),.texture(trans),.texture(environment),.sampler(clampSampler),.buffer(sunBuffer),.texture(lightingTexture)],groups:MTLSize(width:1,height:1,depth:1))
        }
        c.endEncoding()
        if cacheDirty || cadence-lastCache >= 0.125 {
            render(command, target: cachedSky, pipeline: visibleSkyPipeline(), label: "visible sky", resources: [.buffer(frameBuffer),.texture(trans),.texture(skyLUT),.sampler(clampSampler),.texture(cloudNoise),.texture(cloudNoise),.texture(starAtlas),.texture(galaxyAtlas)], skyScissor:options["fullSky"] != "1")
            cacheDirty = false; lastCache = cadence; cachedSkyElapsed = clock.elapsed
        }
        var region=visibleRegion
        if let values=options["visibleRegion"]?.split(separator:",").compactMap({Double($0)}),values.count==4,
           frameIndex>1 {
            region=CGRect(x:values[0],y:values[1],width:values[2],height:values[3])
        }
        if let change=Int(options["regionChangeFrame"] ?? ""),frameIndex>=change,
           let values=options["visibleRegionAfter"]?.split(separator:",").compactMap({Double($0)}),values.count==4 {
            region=CGRect(x:values[0],y:values[1],width:values[2],height:values[3])
        }
        if let reveal=Int(options["revealFrame"] ?? ""),frameIndex>=reveal { region=RegionalRendering.full }
        // Full first frame initializes retained imagery for immediate reveals.
        // Shared multi-display cameras currently fail open to a full frame.
        let outputRegion=RegionalRendering.output(region,width:width,height:height)
        let support = initialized && width==1280 && height==800 && snapshotRequested == nil && !(options["snapshotPath"] != nil && frameIndex==8) && presentationSurfaces.count<=1 && options["regionalRendering"] != "0"
            ? RegionalRendering.hdrSupport(output:outputRegion,width:width,height:height,levels: bloomLevels)
            : CGRect(x:0,y:0,width:width,height:height)
        shadedFraction=Double(support.width*support.height)/Double(width*height)
        let partial=shadedFraction<0.85
        if !partial { shadedFraction=1 }
        if partial {
            do {
                let next=try regionalHistory ?? texture(width,height,"regional HDR history",renderOnly:true)
                regionalHistory=hdr;hdr=next
            } catch { record(error.localizedDescription); return }
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
        if partial,let previous=regionalHistory {
            r.setRenderPipelineState(historyPipeline);r.setDepthStencilState(rainDepthUnoccluded)
            r.setFragmentTexture(previous,index:0)
            r.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3)
            r.setScissorRect(MTLScissorRect(x:Int(support.minX),y:Int(support.minY),width:Int(support.width),height:Int(support.height)))
        }
        let needsGuard = width*2 < height && options["legacyGuard"] != "1"
        r.setRenderPipelineState((clock.stableDetails || weatherActive) ? (needsGuard ? oceanStableGuardPipeline : oceanStablePipeline) : (needsGuard ? oceanGuardPipeline : oceanPipeline)); r.setDepthStencilState(oceanDepth)
        if needsGuard { r.setVertexBuffer(displacementBounds,offset:0,index:13) }
        r.setCullMode(.none)
        bind([.buffer(frameBuffer),.texture(trans),.texture(skyLUT),.sampler(clampSampler),.texture(disp),.texture(deriv),.texture(moments),.texture(foamDetail),.texture(environment),.sampler(repeatSampler),.texture(foam[foamIndex]),.buffer(sunBuffer),.texture(lightingTexture)], to: r, vertexSlots: (1 << 0) | (1 << 4) | (1 << 9))
        r.setFragmentBuffer(cameraWater,offset:0,index:13)
        if !(verificationEnabled && options["skyOnly"] == "1") {
            r.drawIndexedPrimitives(type: .triangle, indexCount: triangleCount*3, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: 0)
        }
        if !(verificationEnabled && options["coverage"] == "1") {
            r.setRenderPipelineState(skyPipeline); r.setDepthStencilState(skyDepth)
            bind([.texture(cachedSky),.sampler(clampSampler),.buffer(frameBuffer),.buffer(cameraWater)], to: r)
            r.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            if let celestialState,celestialState.night>0.001,starCount>0 {
                // Tiny analytic point sprites share this render pass and its
                // sky-only depth test. Cloud integration stays half-resolution.
                r.setRenderPipelineState(starPipeline)
                r.setVertexBuffer(frameBuffer,offset:0,index:0)
                r.setVertexBuffer(starCatalogue,offset:0,index:1)
                r.setFragmentBuffer(frameBuffer,offset:0,index:0)
                r.setFragmentBuffer(cameraWater,offset:0,index:1)
                r.setFragmentTexture(cachedSky,index:2)
                r.setFragmentSamplerState(clampSampler,index:3)
                r.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3,instanceCount:starCount)
            }
        }
        if weatherActive,weatherDynamics.current.rain>0.001,options["rainParticles"] != "0",!(verificationEnabled && options["skyOnly"] == "1") {
            r.setRenderPipelineState(rainPipeline);r.setDepthStencilState(options["rainOcclusion"] == "0" ? rainDepthUnoccluded : rainDepth)
            r.setVertexBuffer(frameBuffer,offset:0,index:0);r.setVertexBuffer(rainBuffer,offset:0,index:1)
            r.setFragmentBuffer(frameBuffer,offset:0,index:0);r.setFragmentBuffer(rainBuffer,offset:0,index:1);r.setFragmentBuffer(cameraWater,offset:0,index:4)
            r.setFragmentTexture(environment,index:2);r.setFragmentSamplerState(clampSampler,index:3)
            r.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:6,instanceCount:120000)
        }
        r.endEncoding()
        for m in 0..<bloomLevels {
            render(command, target: bloom[m], pipeline: downPipeline, label: "bloom down", resources: [.texture(m == 0 ? hdr : bloom[m-1]),.sampler(linearSampler),.buffer(bloomUniforms[m])])
        }
        for m in stride(from: bloomLevels-1, through: 1, by: -1) {
            render(command, target: bloom[m-1], pipeline: upPipeline, label: "bloom up", resources: [.texture(bloom[m]),.sampler(linearSampler),.buffer(bloomUniforms[bloomLevels+m])], load: .load)
        }
        if surfaceDrawables.isEmpty || !acquiredRegions.isEmpty {
            render(command, target: display, pipeline: compositePipeline, label: "composite", resources: [.texture(hdr),.texture(bloom[0]),.sampler(linearSampler),.buffer(compositeBuffer)])
        }
        if !acquiredRegions.isEmpty {
            guard encodeTileCopies(command,source:display,targets:zip(surfaceDrawables,acquiredRegions).map { ($0.0.texture,$0.1) }) else { return }
        } else {
            for surface in surfaceDrawables { encodeSurfaceComposite(command,target:surface.texture) }
        }
        if benchmarkEnabled,let count=Int(options["benchmarkTiles"] ?? ""),(1...4).contains(count),width==1280,height==800 {
            do {
                if benchmarkTileTargets.isEmpty { benchmarkTileTargets=try (0..<4).map { try texture($0==0 || $0==3 ? 321 : 322,800,"benchmark presentation \($0)",format:.bgra8Unorm,renderOnly:true) } }
                let targets=(0..<count).map { (benchmarkTileTargets[$0],CGRect(x:Double($0)/4,y:0,width:0.25,height:1)) }
                guard encodeTileCopies(command,source:display,targets:targets) else { return }
            } catch { record(error.localizedDescription);return }
        }
        if OceanRunMode.offscreen,options["testTiles"]=="1",width==1280,height==800 {
            do {
                var tiles: [(MTLTexture,CGRect)] = []
                for i in 0..<4 {
                    let tileWidth = (i==0 || i==3) ? 321 : 322
                    let tile = try texture(tileWidth,800,"verification tile \(i)",format:.bgra8Unorm,renderOnly:true)
                    let region = CGRect(x:Double(i)/4,y:0,width:0.25,height:1)
                    tiles.append((tile,region))
                }
                guard encodeTileCopies(command,source:display,targets:tiles) else { return }
                let stitched=try texture(width,height,"stitched tile verification",format:.bgra8Unorm,renderOnly:true)
                guard let blit=command.makeBlitCommandEncoder() else { return }
                for (tile,region) in tiles {
                    let visible=RegionalRendering.output(region,width:width,height:height)
                    let padded=RegionalRendering.tileCrop(region,width:width,height:height)
                    blit.copy(from:tile,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:Int(visible.minX-padded.minX),y:0,z:0),sourceSize:MTLSize(width:Int(visible.width),height:tile.height,depth:1),to:stitched,destinationSlice:0,destinationLevel:0,destinationOrigin:MTLOrigin(x:Int(region.minX*CGFloat(width)),y:0,z:0))
                }
                blit.endEncoding();display=stitched
            } catch { record(error.localizedDescription);return }
        }
        let snapshotRowBytes=(width*4+255)/256*256
        var snapshot: MTLBuffer?
        let snapshotCallback=snapshotRequested
        if snapshotCallback != nil || (options["snapshotPath"] != nil && frameIndex==8) {
            do {
                let target=try texture(width,height,"wallpaper snapshot",format:.bgra8Unorm,renderOnly:true)
                render(command,target:target,pipeline:compositePipeline,label:"snapshot",resources:[.texture(hdr),.texture(bloom[0]),.sampler(linearSampler),.buffer(compositeBuffer)])
                snapshot=try buffer(snapshotRowBytes*height,"wallpaper snapshot readback")
                if let blit=command.makeBlitCommandEncoder(),let snapshot {
                    blit.copy(from:target,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:width,height:height,depth:1),to:snapshot,destinationOffset:0,destinationBytesPerRow:snapshotRowBytes,destinationBytesPerImage:snapshotRowBytes*height)
                    blit.endEncoding()
                    snapshotRequested=nil
                }
            } catch { record(error.localizedDescription) }
        }
        let snapshotWidth=width,snapshotHeight=height
        let snapshotBuffer=snapshot
        let verify = verificationEnabled && (sequenceFrames.isEmpty ? frameIndex == max(8,min(3600,Int(options["verifyFrame"] ?? "") ?? 8)) : sequenceFrames.contains(frameIndex))
        let readbacks: [Readback]
        do { readbacks = verify ? try encodeReadbacks(command, display:display) : [] }
        catch { record(error.localizedDescription); return }
        let presenting = surfaceDrawables + (drawable.map { [$0] } ?? [])
        for surface in presenting {
            surface.addPresentedHandler { [weak self] _ in
                DispatchQueue.main.async { self?.presentedDrawables += 1 }
            }
            command.present(surface)
        }
        let profileLabels = profiler?.labels ?? []
        let renderedFrame = frameIndex
        let cpuEncodeMs = benchmarkEnabled ? (CACurrentMediaTime()-now)*1000 : 0
        let threadCPUEncodeMs = benchmarkEnabled ? threadCPUTimeMilliseconds()-cpuThreadStart : 0
        let frameGate=gate
        command.addCompletedHandler { [weak self] completed in
            // ScreenSaver can release its renderer with a frame in flight.
            // Keep the semaphore alive and balanced even after teardown.
            guard let self else { frameGate.signal();return }
            let stageTimes = self.profiler?.resolve(labels: profileLabels) ?? [:]
            let elapsed = (completed.gpuEndTime-completed.gpuStartTime)*1000
            DispatchQueue.main.async {
                // Keep automated timers from submitting another frame before
                // completion counters and verification have consumed this one.
                defer { frameGate.signal() }
                if completed.status == .completed { self.completedFrames += 1 }
                if completed.status == .error { self.record(completed.error?.localizedDescription ?? "Metal command failed") }
                if completed.status == .completed,let snapshotBuffer {
                    var data=Data(count:snapshotWidth*snapshotHeight*4)
                    data.withUnsafeMutableBytes { raw in
                        for row in 0..<snapshotHeight { memcpy(raw.baseAddress!+row*snapshotWidth*4,snapshotBuffer.contents()+row*snapshotRowBytes,snapshotWidth*4) }
                    }
                    snapshotCallback?(data,snapshotWidth,snapshotHeight)
                    if let path=self.options["snapshotPath"] { try? data.write(to:URL(fileURLWithPath:path)) }
                }
                if elapsed > 0 { self.gpuMilliseconds = self.gpuMilliseconds == 0 ? elapsed : self.gpuMilliseconds*0.8+elapsed*0.2 }
                self.profiler?.record(stageTimes, frame:renderedFrame)
                self.frames += 1
                if self.benchmarkEnabled && renderedFrame > 60 { self.benchmarkTimes.append(elapsed); self.benchmarkCPUTimes.append(cpuEncodeMs); self.benchmarkThreadCPUTimes.append(threadCPUEncodeMs) }
                if self.benchmarkEnabled && self.frames >= (Int(self.options["frames"] ?? "") ?? 180) {
                    self.finishBenchmark()
                }
                if verify { self.verify(readbacks) }
            }
        }
        initialized = true
        committed = true
        command.commit();submittedFrames += 1
    }

    private func encodeTileCopies(_ command: MTLCommandBuffer,source: MTLTexture,targets:[(MTLTexture,CGRect)]) -> Bool {
        guard let blit=command.makeBlitCommandEncoder() else { record("Cannot create tile presentation");return false }
        blit.label="shared display crops"
        defer { blit.endEncoding() }
        for (target,region) in targets {
            let rect=RegionalRendering.tileCrop(region,width:source.width,height:source.height)
            guard target.width==Int(rect.width),target.height==Int(rect.height) else { record("Tile drawable \(target.width)x\(target.height) does not match crop \(rect) of \(source.width)x\(source.height)");return false }
            blit.copy(from:source,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:Int(rect.minX),y:Int(rect.minY),z:0),sourceSize:MTLSize(width:target.width,height:target.height,depth:1),to:target,destinationSlice:0,destinationLevel:0,destinationOrigin:MTLOrigin(x:0,y:0,z:0))
        }
        return true
    }

    // Aspect-fill mapping of the shared frame. Wider targets crop around the
    // horizon; narrower targets crop the sides. Equal sizes stay 1:1.
    static func surfaceMapping(source: SIMD2<Float>, target: SIMD2<Float>, horizon: Float) -> SIMD4<Float> {
        guard source.x > 0, source.y > 0, target.x > 0, target.y > 0 else { return SIMD4(1,1,0,0) }
        let a = source.x/source.y, b = target.x/target.y
        if abs(a-b) < 1e-4 { return SIMD4(1,1,0,0) }
        if b > a { let k = a/b; return SIMD4(1,k,0,horizon*(1-k)) }
        let k = b/a; return SIMD4(k,1,0.5*(1-k),0)
    }

    private func encodeSurfaceComposite(_ command: MTLCommandBuffer, target: MTLTexture) {
        if target.width == width && target.height == height {
            render(command, target: target, pipeline: compositePipeline, label: "composite", resources: [.texture(hdr),.texture(bloom[0]),.sampler(linearSampler),.buffer(compositeBuffer)])
            return
        }
        let p = MTLRenderPassDescriptor()
        p.colorAttachments[0].texture = target
        p.colorAttachments[0].loadAction = .dontCare; p.colorAttachments[0].storeAction = .store
        guard let e = command.makeRenderCommandEncoder(descriptor: p) else { record("Cannot create surface pass"); return }
        e.label = "surface composite"
        e.setRenderPipelineState(mirrorPipeline)
        bind([.texture(hdr),.texture(bloom[0]),.sampler(linearSampler),.buffer(compositeBuffer)], to: e)
        var mapping = OceanRenderer.surfaceMapping(source: SIMD2(Float(width),Float(height)), target: SIMD2(Float(target.width),Float(target.height)), horizon: horizonUV)
        e.setFragmentBytes(&mapping, length: MemoryLayout<SIMD4<Float>>.size, index: 4)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        e.endEncoding()
    }

    // Exercise the unchanged-resource-size path using a newly created view.
    // No NSWindow/drawable acquisition is needed by this verification fixture.
    private func verifySurfaceSizing() throws {
        let priorWidth=width,priorHeight=height
        let replacement=MTKView(frame:CGRect(x:0,y:0,width:width,height:height),device:device)
        replacement.autoResizeDrawable=false;replacement.isPaused=true
        replacement.drawableSize=CGSize(width:width*3,height:height*3)
        try updateSize(replacement)
        guard width==priorWidth && height==priorHeight && replacement.drawableSize==CGSize(width:width,height:height) else {
            throw OceanFailure(message:"Recreated surface bypassed the shared pixel budget")
        }
        surfaceSizingVerified=true
        print("PASS: replacement surface retains the shared drawable budget with unchanged HDR dimensions.")
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
                        label: String, resources: [Resource], load: MTLLoadAction = .clear, skyScissor: Bool = false) {
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
        if options["captureDisplayOnly"] == "1" && !sequenceFrames.isEmpty { sources=[("display",display,1,0)] }
        if options["testTiles"]=="1",let source=offscreenDisplay { sources.append(("tile source",source,1,0)) }
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
        if options["dumpWater"] == "1" {
            let snapshot = try buffer(16,"camera water verification")
            blit.copy(from:cameraWater,sourceOffset:0,to:snapshot,destinationOffset:0,size:16)
            outputs.append(Readback(name:"camera water",buffer:snapshot,width:1,height:1,layers:1,rowBytes:16,bytesPerPixel:16))
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
        if let source=outputs.first(where:{$0.name=="tile source"}),let stitched=outputs.first(where:{$0.name=="display"}) {
            guard source.width==stitched.width,source.height==stitched.height else { record("Tile reconstruction dimensions changed");exit(1) }
            for row in 0..<source.height {
                guard memcmp(source.buffer.contents()+row*source.rowBytes,stitched.buffer.contents()+row*stitched.rowBytes,source.width*4)==0 else { record("Tile presentation changed source pixels");exit(1) }
            }
            tilePresentationVerified=true
        }
        if let path = verificationDumpPath {
            for output in outputs where (output.name == "HDR" && options["captureDisplayOnly"] != "1") || output.name == "display" {
                var packed = Data()
                for y in 0..<output.height {
                    packed.append(output.buffer.contents().advanced(by:y*output.rowBytes).assumingMemoryBound(to:UInt8.self),count:output.width*output.bytesPerPixel)
                }
                let destination = output.name == "HDR" ? path : path+".bgra8"
                do { try packed.write(to:URL(fileURLWithPath:destination)) }
                catch { record("Cannot write verification capture: \(error)"); exit(1) }
            }
        }
        if let path = verificationDumpPath, let state=outputs.first(where:{$0.name == "camera water"}) {
            do { try Data(bytes:state.buffer.contents(),count:16).write(to:URL(fileURLWithPath:path+".water")) }
            catch { record("Cannot write water state: \(error)"); exit(1) }
        }
        if let path = verificationDumpPath, options["dumpMips"] == "1" {
            var packed = Data()
            for output in outputs where (output.name.contains(" mip") && !output.name.hasPrefix("environment") && !output.name.hasPrefix("bloom")) || ["displacement","slopes","moments"].contains(output.name) {
                for layer in 0..<output.layers { for y in 0..<output.height {
                    packed.append(output.buffer.contents().advanced(by:layer*output.rowBytes*output.height+y*output.rowBytes).assumingMemoryBound(to:UInt8.self),count:output.width*output.bytesPerPixel)
                } }
            }
            do { try packed.write(to:URL(fileURLWithPath:path+".mips")) }
            catch { record("Cannot write mip capture: \(error)"); exit(1) }
        }
        if let path = verificationDumpPath, options["dumpClouds"] == "1" {
            var packed = Data()
            for output in outputs where output.name == "cached sky" || output.name.hasPrefix("environment") || output.name == "sun visibility" {
                for layer in 0..<output.layers { for y in 0..<output.height {
                    packed.append(output.buffer.contents().advanced(by:layer*output.rowBytes*output.height+y*output.rowBytes).assumingMemoryBound(to:UInt8.self),count:output.width*output.bytesPerPixel)
                } }
            }
            do { try packed.write(to:URL(fileURLWithPath:path+".clouds")) }
            catch { record("Cannot write cloud capture: \(error)"); exit(1) }
        }
        if let path = verificationDumpPath, options["dumpBloom"] == "1" {
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
            if output.name == "camera water" {
                let values=output.buffer.contents().assumingMemoryBound(to:Float.self)
                if !(0..<4).allSatisfy({values[$0].isFinite}) { record("Nonfinite camera water state"); exit(1) }
                continue
            }
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
        print(options["captureDisplayOnly"] == "1" && !sequenceFrames.isEmpty ? "PASS: temporal display/sky capture is finite and nonconstant." : "PASS: all six wave cascades and HDR/display frames contain finite, nonconstant GPU output.")
        fflush(stdout)
        if sequenceFrames.isEmpty || frameIndex >= (sequenceFrames.max() ?? 8) { NSApp.terminate(nil) }
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
        var report: [String:Any] = ["device":device.name,"tilePresentationVerified":tilePresentationVerified,"skyLUTUpdates":skyLUTUpdates,"saverRenderingPaused":hostSaverRendering,"screenLocked":hostLocked,"shadedFraction":shadedFraction,"gpuAllocatedBytes":device.currentAllocatedSize,"width":width,"height":height,"triangles":triangleCount,"indexBits":indexType == .uint16 ? 16 : 32,"indexBytes":indexBuffer.length,
            "cpuThreadEncodeMedianMs":threadCPU[threadCPU.count/2],"cpuThreadEncodeMeanMs":threadCPU.reduce(0,+)/Double(threadCPU.count),
            "cpuEncodeMedianMs":cpu[cpu.count/2],"cpuEncodeMeanMs":cpu.reduce(0,+)/Double(cpu.count),
            "renderTextureUsage":(([hdr,cachedSky] as [MTLTexture?]).compactMap { $0 }+bloom).map { $0.usage.rawValue },"offscreen":OceanRunMode.offscreen,"windowCount":NSApp.windows.count,"activationPolicy":NSApp.activationPolicy().rawValue,"narrowTextureUsage":options["narrowTextureUsage"] != "0","specializedSkyAAMask":specializedSkyAAMask,"skyAAMask":lastSkyAAMask,"fusedEvolution":fusedEvolution,"spectrumBufferBytes":(specA?.length ?? 0)+(specB?.length ?? 0),"sharedCubic":options["sharedCubic"] != "0","skipCloudOctaves":skipCloudOctaves,"cachedSkyElapsed":cachedSkyElapsed,"clockMode":clock.mode.rawValue,"elapsed":clock.elapsed,"stableDetails":clock.stableDetails,"packedJacobian":packedJacobian,"fusedMips":fusedMipmaps, "mipmapRounding":mipmapRounding.rawValue, "dayNightActive":celestialState != nil,"solarCalculations":celestialCycle.calculationCount,"solarCacheWrites":celestialCycle.cacheWriteCount,"galaxyAtlasWidth":galaxyAtlas.width,"galaxyAtlasHeight":galaxyAtlas.height,"starCount":starCount,"starAtlasWidth":starAtlas.width,"starAtlasHeight":starAtlas.height,"sunAltitude":celestialState?.sunAltitude ?? Double(value("sunElev",2.6)),"moonIllumination":celestialState?.moonIllumination ?? 0,"weatherActive":weatherActive,"weatherDetailPhase":(60..<63).map { frameBuffer.contents().assumingMemoryBound(to:Float.self)[$0] },"rain":weatherDynamics.current.rain,"weatherCloud":weatherDynamics.current.cloud,"weatherWind":weatherDynamics.current.wind,"weatherSeverity":weatherDynamics.current.severity,"weatherThunder":weatherDynamics.current.thunder,"seaSettling":seaSettling,"volumetricClouds":options["volumetricClouds"] != "0","cloudNoiseBytes":CloudNoise.size*CloudNoise.size*CloudNoise.size*4,"cloudCacheWidth":cachedSky.width,"cloudCacheHeight":cachedSky.height,"verboseBindings":options["verboseBindings"] == "1", "samples":times.count,"gpuMedianMs":times[times.count/2],"gpuMeanMs":times.reduce(0,+)/Double(times.count),
            "gpuP95Ms":times[min(times.count-1,Int(Double(times.count)*0.95))],
            "gpuStagesMs":profiler?.averageMilliseconds ?? [:],"profiled":profiler != nil,"errors":errors]
        report.merge(daylightDiagnostics()) { _,new in new }
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
        var data: [String: Any] = ["physicalGuard":width*2 < height && options["legacyGuard"] != "1","guardBoundsVerified":verifiedGuardBounds,"renderTextureUsage":(([hdr,cachedSky] as [MTLTexture?]).compactMap { $0 }+bloom).map { $0.usage.rawValue },"offscreen":OceanRunMode.offscreen,"windowCount":NSApp.windows.count,"activationPolicy":NSApp.activationPolicy().rawValue,"narrowTextureUsage":options["narrowTextureUsage"] != "0","specializedSkyAAMask":specializedSkyAAMask,"skyAAMask":lastSkyAAMask,"fusedEvolution":fusedEvolution,"spectrumBufferBytes":(specA?.length ?? 0)+(specB?.length ?? 0),"sharedCubic":options["sharedCubic"] != "0","skipCloudOctaves":skipCloudOctaves,"cachedSkyElapsed":cachedSkyElapsed,"clockMode":clock.mode.rawValue,"elapsed":clock.elapsed,"stableDetails":clock.stableDetails,"packedJacobian":packedJacobian,"fusedMips":fusedMipmaps,"mipmapRounding":mipmapRounding.rawValue,"dayNightActive":celestialState != nil,"solarCalculations":celestialCycle.calculationCount,"solarCacheWrites":celestialCycle.cacheWriteCount,"galaxyAtlasWidth":galaxyAtlas.width,"galaxyAtlasHeight":galaxyAtlas.height,"starCount":starCount,"starAtlasWidth":starAtlas.width,"starAtlasHeight":starAtlas.height,"sunAltitude":celestialState?.sunAltitude ?? Double(value("sunElev",2.6)),"moonIllumination":celestialState?.moonIllumination ?? 0,"weatherActive":weatherActive,"weatherDetailPhase":frames>0 ? (60..<63).map { frameBuffer.contents().assumingMemoryBound(to:Float.self)[$0] } : [Float](repeating:0,count:3),"rain":weatherDynamics.current.rain,"weatherCloud":weatherDynamics.current.cloud,"weatherWind":weatherDynamics.current.wind,"weatherSeverity":weatherDynamics.current.severity,"weatherThunder":weatherDynamics.current.thunder,"seaSettling":seaSettling,"volumetricClouds":options["volumetricClouds"] != "0","cloudNoiseBytes":CloudNoise.size*CloudNoise.size*CloudNoise.size*4,"cloudCacheWidth":cachedSky?.width ?? 0,"cloudCacheHeight":cachedSky?.height ?? 0,"renderer":"Metal", "device":device.name,"tilePresentationVerified":tilePresentationVerified,"skyLUTUpdates":skyLUTUpdates,"saverRenderingPaused":hostSaverRendering,"screenLocked":hostLocked,"shadedFraction":shadedFraction,"gpuAllocatedBytes":device.currentAllocatedSize, "fps":(fps*10).rounded()/10,
            "gpuMs":(gpuMilliseconds*100).rounded()/100, "frames":frames, "paused":isPaused, "governor":governor,
            "width":width, "height":height, "triangles":triangleCount,"indexBits":indexType == .uint16 ? 16 : 32,"indexBytes":indexBuffer?.length ?? 0, "errors":errors, "gpuStagesMs":profiler?.averageMilliseconds ?? [:]]
        data.merge(daylightDiagnostics()) { _,new in new }
        if let encoded = try? JSONSerialization.data(withJSONObject: data, options: .sortedKeys), let text = String(data: encoded, encoding: .utf8) {
            print("Ocean diagnostics: \(text)"); fflush(stdout)
        }
    }
}
