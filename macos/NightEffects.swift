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
        let auto = activity < chance ? (0.35 + 0.65*(1 - activity/chance))*(0.55 + 0.45*polar) : 0
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let day = Double(calendar.ordinality(of: .day, in: .year, for: date.addingTimeInterval(-12*3600)) ?? 1)
        let bloom = hash(night, 0xB1)
        return Levels(aurora: clamp(aurora, 4) ?? auto,
                      meteors: clamp(meteors, 60) ?? showerRate(dayOfYear: day),
                      bioluminescence: clamp(bioluminescence, 4) ?? (bloom < 0.3 ? 0.6 + 0.4*hash(night, 0xB2) : 0))
    }
}
