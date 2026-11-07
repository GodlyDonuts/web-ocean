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
    enum Reason: Hashable { case systemSleep, displaySleep, inactiveSession, screenLocked, screenSaver, saverRendering, userPaused }
    private var reasons: Set<Reason> = []
    var isSuspended: Bool { !reasons.isEmpty }
    func isSuspended(_ reason: Reason) -> Bool { reasons.contains(reason) }
    mutating func set(_ reason: Reason, active: Bool) {
        if active { reasons.insert(reason) } else { reasons.remove(reason) }
    }
}

// Leased activity also covers the Settings preview, which does not emit the
// system's screensaver-start notification. A crashed saver cannot freeze the
// wallpaper indefinitely. All times are monotonic; no new polling timer.
struct SaverActivityTracker {
    private var leases: [String:Double]=[:]
    mutating func rendered(token: String,at time: Double) {
        guard !token.isEmpty,token.count<=128,time.isFinite else { return }
        leases=leases.filter { $0.value>time }
        guard leases.count<32 || leases[token] != nil else { return }
        leases[token]=time+12
    }
    mutating func stopped(token: String) { leases.removeValue(forKey:token) }
    mutating func isActive(at time: Double) -> Bool {
        leases=leases.filter { $0.value>time };return !leases.isEmpty
    }
}
