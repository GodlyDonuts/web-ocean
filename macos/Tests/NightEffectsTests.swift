import Foundation

@main
struct NightEffectsTests {
    static func main() {
        var failures = 0
        func check(_ ok: Bool, _ message: String) { if !ok { print("FAIL: \(message)"); failures += 1 } }
        let zone = TimeZone(identifier: "America/New_York")!
        let evening = Date(timeIntervalSince1970: 1793502000)
        let lateNight = evening.addingTimeInterval(5*3600)
        check(NightEffects.nightIndex(evening, zone: zone) == NightEffects.nightIndex(lateNight, zone: zone), "evening and small hours share a night")
        check(NightEffects.levels(date: evening, zone: zone, latitude: 40) == NightEffects.levels(date: lateNight, zone: zone, latitude: 40), "levels stable within a night")
        let forced = NightEffects.levels(date: evening, zone: zone, latitude: 0, aurora: 9, meteors: -1, bioluminescence: .nan)
        check(forced.aurora == 4 && forced.meteors == 0, "overrides clamp")
        check(forced.bioluminescence == NightEffects.levels(date: evening, zone: zone, latitude: 0).bioluminescence, "NaN override falls back to auto")
        var polar = 0, temperate = 0, bio = 0
        for n in 0..<2000 {
            let date = evening.addingTimeInterval(Double(n)*86400)
            if NightEffects.levels(date: date, zone: zone, latitude: 69).aurora > 0 { polar += 1 }
            let mid = NightEffects.levels(date: date, zone: zone, latitude: 40)
            if mid.aurora > 0 { temperate += 1 }
            if mid.bioluminescence > 0 { bio += 1 }
            check(mid.aurora >= 0 && mid.aurora <= 2.5 && mid.meteors >= 1, "auto ranges")
        }
        check(polar > 1600 && polar < 1900, "polar aurora frequency \(polar)")
        check(temperate > 300 && temperate < 600, "temperate aurora frequency \(temperate)")
        check(bio > 450 && bio < 750, "bioluminescence frequency \(bio)")
        check(NightEffects.showerRate(dayOfYear: 348) > 7 && NightEffects.showerRate(dayOfYear: 180) < 1.1, "Geminids peak, quiet midsummer")
        check(abs(NightEffects.showerRate(dayOfYear: 1) - NightEffects.showerRate(dayOfYear: 366.25)) < 1e-9, "year wraps")
        check(Wildlife.flock(time: 0, sunAltitude: 30, severity: 0, override: 0) == nil, "birds=0 disables flocks")
        check(Wildlife.flock(time: 0, sunAltitude: -30, severity: 1, override: 0.5)?.crossSeconds == 0, "forced flock is mid-view")
        var dusk = 0, day = 0, night = 0, storm = 0
        for n in 0..<20000 {
            let time = 1793502000 + Double(n) * 7
            if Wildlife.flock(time: time, sunAltitude: 3, severity: 0) != nil { dusk += 1 }
            if Wildlife.flock(time: time, sunAltitude: 40, severity: 0) != nil { day += 1 }
            if Wildlife.flock(time: time, sunAltitude: -20, severity: 0) != nil { night += 1 }
            if Wildlife.flock(time: time, sunAltitude: 3, severity: 0.8) != nil { storm += 1 }
        }
        check(dusk > 4000 && dusk < 7500 && day > 1200 && day < dusk, "flock frequency dusk \(dusk) day \(day)")
        check(night == 0 && storm == 0, "no flocks at night or in storms")
        let a = Wildlife.flock(time: 1793502000, sunAltitude: 3, severity: 0), b = Wildlife.flock(time: 1793502000, sunAltitude: 3, severity: 0)
        check(a == b, "flocks deterministic")
        if failures > 0 { exit(1) }
        print("PASS: nightly aurora/meteor/bioluminescence schedule, overrides, latitude frequencies, shower calendar, seabird flocks.")
    }
}
