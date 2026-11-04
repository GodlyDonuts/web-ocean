import Foundation

// A scheduling contract, not a claim that window metadata reveals opaque pixels.
// The presentation layer supplies per-window OS evidence. Unknown state fails open.
enum SurfaceVisibility { case unknown, visible, occluded }
struct SurfaceDemandRequest {
    let surfaceID: String
    let worldID: String
    let visibility: SurfaceVisibility
    let framesPerSecond: Int
    // Callers must include bloom, reflection and reconstruction dependencies.
    let requiredWaveBands: UInt8
}
struct SharedWorldDemand {
    var surfaceIDs: [String] = []
    var presentationHz = 0
    var waveBandHz = [Int](repeating:0,count:6)
    var requiresGPUWork: Bool { !surfaceIDs.isEmpty }
}
enum SharedSurfaceDemand {
    static func plan(_ requests: [SurfaceDemandRequest], suspended: Bool = false) -> [String:SharedWorldDemand] {
        guard !suspended else { return [:] }
        var worlds: [String:SharedWorldDemand] = [:]
        for request in requests {
            if case .occluded = request.visibility { continue }
            let rate = request.framesPerSecond > 0 ? request.framesPerSecond : 30
            let bands: UInt8
            if case .unknown = request.visibility { bands = 0x3f }
            else { bands = request.requiredWaveBands & 0xc0 != 0 ? 0x3f : request.requiredWaveBands }
            var world = worlds[request.worldID] ?? SharedWorldDemand()
            if !world.surfaceIDs.contains(request.surfaceID) { world.surfaceIDs.append(request.surfaceID) }
            world.presentationHz = max(world.presentationHz,rate)
            for band in 0..<6 where bands & (1 << band) != 0 {
                world.waveBandHz[band] = max(world.waveBandHz[band],rate)
            }
            worlds[request.worldID] = world
        }
        return worlds
    }
}

// Reasons are independent: a wake notification must not clear an inactive session.
struct SurfaceSuspensionState {
    enum Reason: Hashable { case systemSleep, displaySleep, inactiveSession }
    private var reasons: Set<Reason> = []
    var isSuspended: Bool { !reasons.isEmpty }
    mutating func set(_ reason: Reason, active: Bool) {
        if active { reasons.insert(reason) } else { reasons.remove(reason) }
    }
}
