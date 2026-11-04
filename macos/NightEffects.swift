import Foundation

// Nightly sky events. Each local night draws its own deterministic activity so
// the wallpaper differs night to night while restarts within a night agree.
enum NightEffects {
    struct Levels: Equatable {
        var aurora = 0.0
        var meteors = 0.0
        var bioluminescence = 0.0
    }

    // Peak day of year, peak relative rate, half-width in days.
    static let showers: [(day: Double, rate: Double, width: Double)] = [
        (3, 4, 1), (112, 1.5, 1.5), (126, 2, 3), (224, 6, 3), (294, 2, 3), (321, 2, 1.5), (348, 7, 2),
    ]

    static func hash(_ n: Int64, _ salt: UInt64) -> Double {
        var x = UInt64(bitPattern: n) &* 0x9E3779B97F4A7C15 ^ salt
        x ^= x >> 30; x = x &* 0xBF58476D1CE4E5B9
        x ^= x >> 27; x = x &* 0x94D049BB133111EB
        x ^= x >> 31
        return Double(x >> 11) / Double(1 << 53)
    }

    static func nightIndex(_ date: Date, zone: TimeZone) -> Int64 {
        let local = date.timeIntervalSince1970 + Double(zone.secondsFromGMT(for: date)) - 12*3600
        return Int64((local/86400).rounded(.down))
    }

    static func showerRate(dayOfYear: Double) -> Double {
        showers.reduce(1) { total, shower in
            var d = abs(dayOfYear - shower.day); d = min(d, 365.25 - d)
            return total + shower.rate*exp(-0.5*(d/shower.width)*(d/shower.width))
        }
    }

    static func levels(date: Date, zone: TimeZone, latitude: Double?, aurora: Double? = nil,
                       meteors: Double? = nil, bioluminescence: Double? = nil) -> Levels {
        func clamp(_ value: Double?, _ upper: Double) -> Double? {
            guard let value, value.isFinite else { return nil }
            return max(0, min(upper, value))
        }
        let night = nightIndex(date, zone: zone)
        let lat = abs(latitude ?? 40)
        let polar = min(1, max(0, (lat-50)/17))
        let activity = hash(night, 0xA0)
        let chance = 0.22 + 0.68*polar
        let auto = activity < chance ? 2.5*(0.35 + 0.65*(1 - activity/chance))*(0.55 + 0.45*polar) : 0
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let day = Double(calendar.ordinality(of: .day, in: .year, for: date.addingTimeInterval(-12*3600)) ?? 1)
        let bloom = hash(night, 0xB1)
        return Levels(aurora: clamp(aurora, 4) ?? auto,
                      meteors: clamp(meteors, 60) ?? showerRate(dayOfYear: day),
                      bioluminescence: clamp(bioluminescence, 4) ?? (bloom < 0.3 ? 0.6 + 0.4*hash(night, 0xB2) : 0))
    }
}

/// Deterministic seabird flock schedule: 150 s windows, most often around sunrise and sunset.
enum Wildlife {
    struct Flock: Equatable {
        var crossSeconds: Double
        var seed: Double
        var direction: Double
        var count: Int
    }
    static let window = 150.0, duration = 70.0

    static func flock(time: Double, sunAltitude: Double, severity: Double, override: Double? = nil) -> Flock? {
        if let forced = override, forced.isFinite {
            guard forced > 0 else { return nil }
            return Flock(crossSeconds: (min(forced, 1) - 0.5) * duration, seed: 0.37, direction: 1, count: 40)
        }
        guard time.isFinite, severity < 0.6, sunAltitude > -5 else { return nil }
        let chance = sunAltitude < 12 ? 0.6 : 0.25
        let index = Int64((time / window).rounded(.down))
        guard NightEffects.hash(index, 0xB1D5) < chance else { return nil }
        let start = NightEffects.hash(index, 0xB1D6) * (window - duration)
        let local = time - Double(index) * window - start
        guard local >= 0, local <= duration else { return nil }
        return Flock(crossSeconds: local - duration / 2, seed: NightEffects.hash(index, 0xB1D7) * 97,
                     direction: NightEffects.hash(index, 0xB1D8) < 0.5 ? -1 : 1,
                     count: 18 + Int(NightEffects.hash(index, 0xB1D9) * 40))
    }
}

/// Storm waterspouts: 15-minute windows, about a third of them in moderate storms.
enum StormEvents {
    static let window = 900.0, duration = 300.0, fade = 40.0

    /// (strength, seed, azimuth offset) or nil.
    static func waterspout(time: Double, severity: Double, override: Double? = nil) -> SIMD3<Double>? {
        if let forced = override, forced.isFinite {
            guard forced > 0 else { return nil }
            return SIMD3(min(forced, 1.5), 0.4, 0.12)
        }
        guard time.isFinite, severity > 0.3, severity < 0.9 else { return nil }
        let index = Int64((time / window).rounded(.down))
        guard NightEffects.hash(index, 0x5B07) < 0.35 else { return nil }
        let start = NightEffects.hash(index, 0x5B08) * (window - duration)
        let local = time - Double(index) * window - start
        guard local >= 0, local <= duration else { return nil }
        let ramp = min(1, local / fade, (duration - local) / fade)
        let storm = min(1, (severity - 0.3) / 0.2) * min(1, (0.9 - severity) / 0.1)
        let strength = ramp * storm
        guard strength > 0.001 else { return nil }
        return SIMD3(strength, NightEffects.hash(index, 0x5B09), (NightEffects.hash(index, 0x5B0A) - 0.5) * 0.9)
    }
}

/// Noctilucent clouds: electric-blue mesospheric ripples, still sunlit at 82 km while
/// the sea is in deep twilight. Summer only, 50-70 degrees latitude, about every other night.
enum Noctilucent {
    static func strength(date: Date, zone: TimeZone, latitude: Double?, sunAltitude: Double, override: Double? = nil) -> Double {
        let twilight = smooth(-3.5, -6.5, sunAltitude) * (1 - smooth(-13, -17, sunAltitude))
        if let override, override.isFinite { return max(0, min(2, override)) * twilight }
        guard let latitude, twilight > 0 else { return 0 }
        let lat = abs(latitude)
        let band = smooth(46, 52, lat) * (1 - smooth(66, 72, lat))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let day = Double(calendar.ordinality(of: .day, in: .year, for: date.addingTimeInterval(-12*3600)) ?? 1)
        var d = abs(day - (latitude >= 0 ? 185 : 4)); d = min(d, 365.25 - d)
        let season = exp(-0.5*(d/22)*(d/22))
        let night = NightEffects.nightIndex(date, zone: zone)
        guard NightEffects.hash(night, 0xC1) < 0.45 else { return 0 }
        return band * season * twilight * (0.5 + 0.5*NightEffects.hash(night, 0xC2))
    }

    private static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - a)/(b - a))); return t*t*(3 - 2*t)
    }
}
