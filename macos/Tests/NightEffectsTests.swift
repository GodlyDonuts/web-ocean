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
        if failures > 0 { exit(1) }
        print("PASS: nightly aurora/meteor/bioluminescence schedule, overrides, latitude frequencies, shower calendar.")
    }
}
