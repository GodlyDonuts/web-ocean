import Foundation
import simd

@main enum CelestialCycleTests {
    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from:value)! }
    static func angle(_ a: SIMD3<Double>,_ b: SIMD3<Double>) -> Double { acos(max(-1,min(1,simd_dot(a,b))))/CelestialMath.rad }
    static func main() throws {
        let ny=ObserverLocation(latitude:40.7128,longitude:-74.006),zone=TimeZone(identifier:"America/New_York")!
        let now=date("2026-10-30T16:00:00Z")
        let today=CelestialMath.makeDay(date:now,location:ny,zone:zone)
        precondition(today.isValid && today.daylight=="normal")
        precondition(today.civilDawn!<today.sunrise! && today.sunrise!<today.solarNoon && today.solarNoon<today.sunset! && today.sunset!<today.civilDusk!)
        // Independent NOAA fractional-year formula (less accurate than the USNO
        // coordinate/root calculation) should agree to within a few minutes.
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(secondsFromGMT:0)!
        let dayOfYear=Double(calendar.ordinality(of:.day,in:.year,for:now)!)
        let gamma=2*Double.pi/365*(dayOfYear-1)
        let eq=229.18*(0.000075+0.001868*cos(gamma)-0.032077*sin(gamma)-0.014615*cos(2*gamma)-0.040849*sin(2*gamma))
        let dec=0.006918-0.399912*cos(gamma)+0.070257*sin(gamma)-0.006758*cos(2*gamma)+0.000907*sin(2*gamma)-0.002697*cos(3*gamma)+0.00148*sin(3*gamma)
        let lat=ny.latitude*CelestialMath.rad
        let ha=acos((cos(90.833*CelestialMath.rad)-sin(lat)*sin(dec))/(cos(lat)*cos(dec)))/CelestialMath.rad
        let midnight=date("2026-10-30T00:00:00Z").timeIntervalSince1970
        let noaaRise=midnight+(720-4*(ny.longitude+ha)-eq)*60
        let noaaSet=midnight+(720-4*(ny.longitude-ha)-eq)*60
        precondition(abs(today.sunrise!-noaaRise)<240 && abs(today.sunset!-noaaSet)<240)
        for stamp in [today.sunrise!,today.sunset!] {
            let s=CelestialMath.state(CelestialMath.sample(stamp),at:stamp,location:ny,heading:270)
            precondition(abs(s.sunAltitude+0.833)<0.00001)
            precondition(abs(asin(s.apparentSun.y)/CelestialMath.rad+0.2663)<0.001)
        }
        for (stamp,hours) in [("2026-03-08T16:00:00Z",23),("2026-11-01T16:00:00Z",25)] {
            let d=CelestialMath.makeDay(date:date(stamp),location:ny,zone:zone)
            precondition(d.isValid && d.end-d.start==Double(hours*3600) && d.samples.count==hours+1)
        }
        let pole=ObserverLocation(latitude:89,longitude:0)
        let polarDay=CelestialMath.makeDay(date:date("2026-06-21T12:00:00Z"),location:pole,zone:zone)
        let polarNight=CelestialMath.makeDay(date:date("2026-12-21T12:00:00Z"),location:pole,zone:zone)
        precondition(polarDay.daylight=="polarDay" && polarDay.sunrise==nil && polarDay.sunset==nil)
        precondition(polarNight.daylight=="polarNight" && polarNight.sunrise==nil && polarNight.sunset==nil)
        var maxSolarError=0.0,maxLunarError=0.0
        let locations=[ny,ObserverLocation(latitude:0,longitude:179.9),ObserverLocation(latitude:-33.86,longitude:151.2),ObserverLocation(latitude:90,longitude:-180),ObserverLocation(latitude:-90,longitude:180)]
        for location in locations { for stamp in ["2026-03-20T12:00:00Z","2026-06-21T12:00:00Z","2026-09-22T12:00:00Z","2026-12-21T12:00:00Z"] {
            let d=CelestialMath.makeDay(date:date(stamp),location:location,zone:zone);precondition(d.isValid)
            for i in 0..<96 {
                let t=d.start+(d.end-d.start)*Double(i)/96
                let exact=CelestialMath.sample(t),cached=CelestialMath.interpolate(d,time:t)
                maxSolarError=max(maxSolarError,angle(exact.sun,cached.sun));maxLunarError=max(maxLunarError,angle(exact.moon,cached.moon))
                let state=CelestialMath.state(cached,at:t,location:location,heading:270)
                precondition(abs(simd_length(state.sun)-1)<1e-10 && abs(simd_length(state.moon)-1)<1e-10 && (0...1).contains(state.moonIllumination))
            }
        } }
        precondition(maxSolarError<0.001 && maxLunarError<0.01)
        let t=now.timeIntervalSince1970
        let first=CelestialMath.state(CelestialMath.sample(t),at:t,location:ny,heading:270)
        let later=CelestialMath.state(CelestialMath.sample(t+3600),at:t+3600,location:ny,heading:270)
        precondition(abs(simd_determinant(first.skyBasis)-1)<1e-10)
        precondition(abs(angle(first.skyBasis[0],later.skyBasis[0])-15.04106864)<0.00001)
        precondition(angle(first.sun,CelestialMath.scene(CelestialMath.local(CelestialMath.sample(t).sun,time:t,location:ny),heading:270))<0.00001)
        let newMoon=CelestialMath.sample(date("2024-04-08T18:00:00Z").timeIntervalSince1970)
        let fullMoon=CelestialMath.sample(date("2024-03-25T07:00:00Z").timeIntervalSince1970)
        precondition((1-simd_dot(newMoon.sun,newMoon.moon))/2<0.01)
        precondition((1-simd_dot(fullMoon.sun,fullMoon.moon))/2>0.99)
        let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:temp) }
        let cache=temp.appendingPathComponent("days.json")
        // Synthetic fixture data must round-trip even if the test Mac is locked.
        // Production caches retain file protection by default.
        let cycle=CelestialCycle(cacheURL:cache,protectCache:false);cycle.location=ny
        let start=Date();_=cycle.state(at:now,zone:zone)
        let calculationMs=Date().timeIntervalSince(start)*1000
        let loopStart=Date()
        for i in 0..<10000 { _=cycle.state(at:now.addingTimeInterval(Double(i)/30),zone:zone) }
        let interpolationMicroseconds=Date().timeIntervalSince(loopStart)*1e6/10000
        precondition(cycle.calculationCount==1 && cycle.cacheWriteCount==1)
        let reload=CelestialCycle(cacheURL:cache,protectCache:false);reload.location=ny;_=reload.state(at:now,zone:zone)
        precondition(reload.calculationCount==0 && reload.cacheWriteCount==0)
        _=reload.state(at:now.addingTimeInterval(86400),zone:zone);precondition(reload.calculationCount==1)
        _=reload.state(at:now,zone:zone);precondition(reload.calculationCount==1)
        reload.location=ObserverLocation(latitude:-33.86,longitude:151.2);_=reload.state(at:now,zone:zone);precondition(reload.calculationCount==2)
        try Data("invalid cache".utf8).write(to:cache)
        let recover=CelestialCycle(cacheURL:cache,protectCache:false);recover.location=ny;_=recover.state(at:now,zone:zone)
        precondition(recover.calculationCount==1 && recover.day!.isValid)
        precondition(CelestialCycle().state(at:now)==nil)
        precondition(!ObserverLocation(latitude:91,longitude:0).isValid && !ObserverLocation(latitude:0,longitude:.nan).isValid)
        let north=CelestialMath.scene(SIMD3(0,0,1),heading:0),west=CelestialMath.scene(SIMD3(-1,0,0),heading:270)
        precondition(simd_length(north-SIMD3(0,0,-1))<1e-10 && simd_length(west-SIMD3(0,0,-1))<1e-10)
        print("PASS: offline events, NOAA cross-check, DST, polar cases, 1,920 interpolated states, moon phases, heading, disk cache/recovery and 10,000 frames with one calculation/write.")
        print("Daily calculation + write: \(calculationMs) ms; cached frame: \(interpolationMicroseconds) µs; interpolation errors sun \(maxSolarError)°, moon \(maxLunarError)° (vs same model, not reference ephemeris).")
        print("Synthetic NYC sunrise UTC: \(Date(timeIntervalSince1970:today.sunrise!)), sunset UTC: \(Date(timeIntervalSince1970:today.sunset!))")
    }
}
