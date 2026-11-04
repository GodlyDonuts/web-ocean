import Foundation
import simd

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
        check(StormEvents.waterspout(time: 0, severity: 0, override: 1) != nil && StormEvents.waterspout(time: 0, severity: 0.6, override: 0) == nil, "spout override")
        var spouts = 0, calm = 0
        for n in 0..<20000 {
            let time = 1793502000 + Double(n) * 9
            if StormEvents.waterspout(time: time, severity: 0.6) != nil { spouts += 1 }
            if StormEvents.waterspout(time: time, severity: 0.1) != nil { calm += 1 }
        }
        check(calm == 0 && spouts > 1000 && spouts < 4000, "waterspout frequency \(spouts)")
        let london = TimeZone(identifier: "Europe/London")!
        check(Noctilucent.strength(date: Date(timeIntervalSince1970: 0), zone: london, latitude: 0, sunAltitude: -10, override: 1) > 0.99, "nlc override")
        check(Noctilucent.strength(date: Date(timeIntervalSince1970: 0), zone: london, latitude: 56, sunAltitude: 5, override: 1) == 0, "nlc needs deep twilight")
        var summer = 0, winter = 0, tropics = 0
        for n in 0..<50 {
            let july = Date(timeIntervalSince1970: 1781051400 + Double(n)*86400), december = Date(timeIntervalSince1970: 1796862600 + Double(n)*86400)
            if Noctilucent.strength(date: july, zone: london, latitude: 56, sunAltitude: -10) > 0.05 { summer += 1 }
            if Noctilucent.strength(date: december, zone: london, latitude: 56, sunAltitude: -10) > 0.01 { winter += 1 }
            if Noctilucent.strength(date: july, zone: london, latitude: 15, sunAltitude: -10) > 0.01 { tropics += 1 }
        }
        check(summer > 8 && summer < 35 && winter == 0 && tropics == 0, "noctilucent season summer \(summer) winter \(winter) tropics \(tropics)")
        check(Comets.apparition(night: 5, override: 0) == nil && Comets.apparition(night: 5, override: 1) != nil, "comet override")
        var cometNights = 0
        for night in Int64(20000)..<Int64(24000) where Comets.apparition(night: night) != nil { cometNights += 1 }
        check(cometNights > 250 && cometNights < 800, "comet frequency \(cometNights)")
        check(Comets.apparition(night: 20123) == Comets.apparition(night: 20123), "comet deterministic")
        let sun = simd_normalize(SIMD3<Double>(0.9, -0.2, 0.1)), head = Comets.head(sun: sun, Comets.Apparition(brightness: 1, elongation: 0.6, tilt: 0.3, tailLength: 0.3, curl: 0.8))
        check(abs(acos(simd_dot(sun, head)) - 0.6) < 1e-9 && head.y > sun.y, "comet head elongation")
        if failures > 0 { exit(1) }
        print("PASS: nightly aurora/meteor/bioluminescence schedule, overrides, latitude frequencies, shower calendar, seabird flocks, waterspouts, noctilucent clouds, comets.")
    }
}
