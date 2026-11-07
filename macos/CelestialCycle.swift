import Foundation
import simd

struct DaylightTime: Equatable {
    enum Mode: String, CaseIterable { case automatic,sunrise,midday,goldenHour,sunset,midnight,custom }
    let mode: Mode
    let minutes: Int
    init(mode: Mode = .automatic, minutes: Int = 0) {
        self.mode=mode;self.minutes=max(0,min(1439,minutes))
    }
    init?(value: String) {
        if let mode=Mode(rawValue:value),mode != .custom { self.init(mode:mode);return }
        let parts=value.split(separator:":",omittingEmptySubsequences:false)
        guard parts.count==2,parts.allSatisfy({$0.count==2 && $0.allSatisfy({$0.isASCII && $0.isNumber})}),
              let hour=Int(parts[0]),let minute=Int(parts[1]),(0...23).contains(hour),(0...59).contains(minute) else { return nil }
        self.init(mode:.custom,minutes:hour*60+minute)
    }
    var value: String { mode == .custom ? String(format:"%02d:%02d",minutes/60,minutes%60) : mode.rawValue }
    func date(reference: Date, day: SolarDay, zone: TimeZone) -> Date? {
        switch mode {
        case .automatic: return reference
        case .sunrise: return day.sunrise.map(Date.init(timeIntervalSince1970:))
        case .midday: return Date(timeIntervalSince1970:day.solarNoon)
        case .goldenHour: return day.sunset.map { Date(timeIntervalSince1970:$0-min(2700,max(0,($0-(day.sunrise ?? day.start))*0.25))) }
        case .sunset: return day.sunset.map(Date.init(timeIntervalSince1970:))
        case .midnight,.custom:
            var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone
            let minute=mode == .midnight ? 0 : minutes
            return calendar.date(bySettingHour:minute/60,minute:minute%60,second:0,of:reference,
                                 matchingPolicy:.nextTime,repeatedTimePolicy:.first,direction:.forward)
        }
    }
}

struct ObserverLocation: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    var isValid: Bool { latitude.isFinite && longitude.isFinite && abs(latitude)<=90 && abs(longitude)<=180 }
}
struct EquatorialSample: Codable {
    let time: Double
    let sun: SIMD3<Double>
    let moon: SIMD3<Double>
    let sunDistanceAU: Double
    let moonDistanceKm: Double
}
struct SolarDay: Codable {
    static let version = 1
    let version: Int
    let location: ObserverLocation
    let timeZoneID: String
    let start: Double
    let end: Double
    let sunrise: Double?
    let sunset: Double?
    let civilDawn: Double?
    let civilDusk: Double?
    let solarNoon: Double
    let daylight: String // normal, polarDay, polarNight, partial
    let samples: [EquatorialSample]
    func matches(_ date: Date, location: ObserverLocation, zone: TimeZone) -> Bool {
        version==Self.version && self.location==location && timeZoneID==zone.identifier && date.timeIntervalSince1970>=start && date.timeIntervalSince1970<end
    }
    var isValid: Bool {
        guard version==Self.version,location.isValid,start.isFinite,end.isFinite,end>start,
              end-start<=26*3600,samples.count>=24,samples.count<=28,
              samples.first?.time==start,samples.last?.time==end else { return false }
        for (i,s) in samples.enumerated() {
            if !s.time.isFinite || (i>0 && s.time<=samples[i-1].time) ||
                !s.sunDistanceAU.isFinite || !(0.98...1.02).contains(s.sunDistanceAU) ||
                !s.moonDistanceKm.isFinite || !(330000...430000).contains(s.moonDistanceKm) { return false }
            for v in [s.sun,s.moon] { if !(0.999...1.001).contains(simd_length(v)) { return false } }
        }
        return [sunrise,sunset,civilDawn,civilDusk,solarNoon].compactMap{$0}.allSatisfy{$0.isFinite && $0>=start && $0<end}
    }
}
struct CelestialState {
    let skyBasis: simd_double3x3 // equatorial-to-scene rotation, shared by stars/bodies
    let sun: SIMD3<Double> // geometric scene direction
    let apparentSun: SIMD3<Double>
    let moon: SIMD3<Double> // topocentric apparent scene direction
    let moonIllumination: Double
    let sunRadius: Double
    let moonRadius: Double
    let sunAltitude: Double // geometric degrees
    let night: Double
}

// Presentation is independent of the astronomical direction: repositioning
// the Moon must not turn its real crescent into a full disk or reverse waxing.
enum WallpaperSky {
    static func direction(progress: Double, horizontalTangent: Double) -> SIMD3<Double> {
        let angle=Double.pi*progress
        // Both bodies share the middle of the fixed shot, not the full sky.
        let halfWidth=atan(max(0.05,horizontalTangent)*0.28)
        let azimuth = -halfWidth*cos(angle)
        let elevation=18*CelestialMath.rad*sin(angle)
        return SIMD3(sin(azimuth)*cos(elevation),sin(elevation),-cos(azimuth)*cos(elevation))
    }
    static func diskAxes(_ center: SIMD3<Double>) -> (SIMD3<Double>,SIMD3<Double>) {
        let axis=abs(center.y)>0.99 ? SIMD3<Double>(1,0,0) : SIMD3<Double>(0,1,0)
        let right=simd_normalize(simd_cross(center,axis))
        return (right,simd_cross(right,center))
    }
    static func phaseLight(state: CelestialState, displayedMoon: SIMD3<Double>) -> SIMD3<Double> {
        let (realRight,realUp)=diskAxes(state.moon)
        let (right,up)=diskAxes(displayedMoon)
        let tangent=SIMD2(simd_dot(state.sun,realRight),simd_dot(state.sun,realUp))
        let orientation=simd_length(tangent)>1e-10 ? simd_normalize(tangent) : SIMD2(1.0,0.0)
        let radial=1-2*state.moonIllumination
        return displayedMoon*radial+(right*orientation.x+up*orientation.y)*sqrt(max(0,1-radial*radial))
    }
}

// Pure offline astronomy. Solar coordinates: USNO approximate almanac equations.
// Moon: low-precision mean-element model (see docs/day-night-cycle.md), with
// observer parallax. This is visual astronomy, not a navigation ephemeris.
enum CelestialMath {
    static let rad = Double.pi/180
    static func radians(_ degrees: Double) -> Double { degrees.truncatingRemainder(dividingBy:360)*rad }
    static func days(_ time: Double) -> Double { time/86400+2440587.5-2451545 }
    static func equatorial(longitude: Double, latitude: Double, obliquity: Double) -> SIMD3<Double> {
        let x=cos(latitude)*cos(longitude), y=cos(latitude)*sin(longitude), z=sin(latitude)
        return simd_normalize(SIMD3(x,y*cos(obliquity)-z*sin(obliquity),y*sin(obliquity)+z*cos(obliquity)))
    }
    static func sample(_ time: Double) -> EquatorialSample {
        let d=days(time),g=radians(357.529+0.98560028*d),q=radians(280.459+0.98564736*d)
        let longitude=q+rad*(1.915*sin(g)+0.020*sin(2*g)),e=radians(23.439-0.00000036*d)
        let sun=equatorial(longitude:longitude,latitude:0,obliquity:e)
        let m=radians(134.963+13.064993*d),f=radians(93.272+13.229350*d)
        let l=radians(218.316+13.176396*d)+rad*6.289*sin(m)
        let b=rad*5.128*sin(f)
        return EquatorialSample(time:time,sun:sun,moon:equatorial(longitude:l,latitude:b,obliquity:e),sunDistanceAU:1.00014-0.01671*cos(g)-0.00014*cos(2*g),moonDistanceKm:385001-20905*cos(m))
    }
    static func sidereal(_ time: Double, longitude: Double) -> Double {
        radians(280.46061837+360.98564736629*days(time)+longitude)
    }
    // Local coordinates: east, up, north. Heading is clockwise from north;
    // scene forward is -Z. The camera stays fixed as the sky rotates past it.
    static func local(_ equatorial: SIMD3<Double>, time: Double, location: ObserverLocation, distance: Double? = nil) -> SIMD3<Double> {
        let theta=sidereal(time,longitude:location.longitude),phi=location.latitude*rad
        let up=SIMD3(cos(phi)*cos(theta),cos(phi)*sin(theta),sin(phi))
        var body=equatorial
        if let distance { body=simd_normalize(equatorial*distance-up*6378.137) }
        let east=SIMD3(-sin(theta),cos(theta),0)
        let north=SIMD3(-sin(phi)*cos(theta),-sin(phi)*sin(theta),cos(phi))
        return SIMD3(simd_dot(body,east),simd_dot(body,up),simd_dot(body,north))
    }
    static func scene(_ local: SIMD3<Double>, heading: Double) -> SIMD3<Double> {
        let a=radians(heading)
        return SIMD3(local.x*cos(a)-local.z*sin(a),local.y,-(local.x*sin(a)+local.z*cos(a)))
    }
    static func refracted(_ direction: SIMD3<Double>) -> SIMD3<Double> {
        let altitude=asin(max(-1,min(1,direction.y)))/rad
        guard altitude > -2.0 && altitude < 89.9 else { return direction }
        // Bennett approximation above -1 degree. A smooth tail below it
        // avoids snapping the sun/Moon direction at the formula's cutoff.
        // The visible horizon correction and stored solar timings are unchanged.
        let correction: Double
        if altitude < -1 {
            correction=0.5667*smooth(-2,-1,altitude)
        } else {
            correction=min(0.5667,(1.02/tan((altitude+10.3/(altitude+5.11))*rad))/60)
        }
        let h=(altitude+correction)*rad
        let horizontal=hypot(direction.x,direction.z)
        guard horizontal>1e-10 else { return direction }
        return SIMD3(direction.x/horizontal*cos(h),sin(h),direction.z/horizontal*cos(h))
    }
    static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t=max(0,min(1,(x-a)/(b-a))); return t*t*(3-2*t)
    }
    static func state(_ s: EquatorialSample, at time: Double, location: ObserverLocation, heading: Double) -> CelestialState {
        let theta=sidereal(time,longitude:location.longitude),phi=location.latitude*rad,h=radians(heading)
        let up=SIMD3(cos(phi)*cos(theta),cos(phi)*sin(theta),sin(phi))
        let east=SIMD3(-sin(theta),cos(theta),0),north=SIMD3(-sin(phi)*cos(theta),-sin(phi)*sin(theta),cos(phi))
        let right=east*cos(h)-north*sin(h),forward=east*sin(h)+north*cos(h)
        let basis=simd_double3x3(columns:(SIMD3(right.x,up.x,-forward.x),SIMD3(right.y,up.y,-forward.y),SIMD3(right.z,up.z,-forward.z)))
        let sun=basis*s.sun,moon=simd_normalize(basis*s.moon*s.moonDistanceKm-SIMD3(0,6378.137,0))
        let phase=max(0,min(1,(1-simd_dot(s.sun,s.moon))*0.5))
        let altitude=asin(max(-1,min(1,sun.y)))/rad
        return CelestialState(skyBasis:basis,sun:sun,apparentSun:refracted(sun),moon:refracted(moon),moonIllumination:phase,sunRadius:0.2666/s.sunDistanceAU*rad,moonRadius:asin(1737.4/s.moonDistanceKm),sunAltitude:altitude,night:1-smooth(-12,-3,altitude))
    }
    static func interpolate(_ day: SolarDay, time: Double) -> EquatorialSample {
        // Normally one direct lookup into 25 hourly samples; DST days can have
        // 24 or 26. There are no full ephemeris evaluations in the frame loop.
        let i=min(day.samples.count-2,max(0,Int((time-day.start)/3600)))
        let a=day.samples[i],b=day.samples[i+1]
        let t=max(0,min(1,(time-a.time)/(b.time-a.time)))
        return EquatorialSample(time:time,sun:simd_normalize(a.sun*(1-t)+b.sun*t),moon:simd_normalize(a.moon*(1-t)+b.moon*t),sunDistanceAU:a.sunDistanceAU*(1-t)+b.sunDistanceAU*t,moonDistanceKm:a.moonDistanceKm*(1-t)+b.moonDistanceKm*t)
    }
    static func makeDay(date: Date, location: ObserverLocation, zone: TimeZone) -> SolarDay {
        precondition(location.isValid)
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone
        let interval=calendar.dateInterval(of:.day,for:date)!
        let start=interval.start.timeIntervalSince1970,end=interval.end.timeIntervalSince1970
        func altitude(_ time: Double) -> Double { asin(max(-1,min(1,local(sample(time).sun,time:time,location:location).y)))/rad }
        func crossings(_ target: Double) -> (Double?,Double?) {
            var rise: Double?,set: Double?
            var a=start,fa=altitude(a)-target
            while a<end {
                let b=min(end,a+600),fb=altitude(b)-target
                if (fa<0 && fb>=0) || (fa>=0 && fb<0) {
                    var lo=a,hi=b
                    for _ in 0..<20 {
                        let mid=(lo+hi)*0.5
                        if (altitude(mid)-target>=0)==(fa>=0) { lo=mid } else { hi=mid }
                    }
                    let crossing=(lo+hi)*0.5
                    if crossing<end { if fa<0 { rise=crossing } else { set=crossing } }
                }
                a=b;fa=fb
            }
            return (rise,set)
        }
        let (rise,set)=crossings(-0.833), (dawn,dusk)=crossings(-6)
        var maximum = -90.0,minimum=90.0,noon=start
        for i in 0...Int(ceil((end-start)/600)) {
            let t=min(end-0.001,start+Double(i)*600),a=altitude(t)
            if a>maximum { maximum=a;noon=t };minimum=min(minimum,a)
        }
        var lo=max(start,noon-600),hi=min(end-0.001,noon+600)
        for _ in 0..<24 { let a=lo+(hi-lo)/3,b=hi-(hi-lo)/3; if altitude(a)<altitude(b) { lo=a } else { hi=b } }
        noon=(lo+hi)/2
        var times=[Double]();var t=start
        while t<end { times.append(t);t+=3600 };times.append(end)
        let status=rise != nil && set != nil ? "normal" : minimum > -0.833 ? "polarDay" : maximum < -0.833 ? "polarNight" : "partial"
        return SolarDay(version:SolarDay.version,location:location,timeZoneID:zone.identifier,start:start,end:end,sunrise:rise,sunset:set,civilDawn:dawn,civilDusk:dusk,solarNoon:noon,daylight:status,samples:times.map(sample))
    }
}

final class CelestialCycle {
    private struct Archive: Codable { let days: [SolarDay] }
    private let cacheURL: URL?
    private var archive: [SolarDay]=[]
    private(set) var day: SolarDay?
    private(set) var calculationCount=0
    private(set) var cacheWriteCount=0
    private(set) var cacheError: String?
    private var moonNightSpan: (start: Double,end: Double)?
    var location: ObserverLocation? { didSet { if oldValue != location { day=nil;moonNightSpan=nil } } }
    var heading=270.0 // geographic west, fixed view; camera does not chase the sun
    init(cacheURL: URL? = nil) {
        self.cacheURL=cacheURL
        if let url=cacheURL,let data=try? Data(contentsOf:url),let saved=try? JSONDecoder().decode(Archive.self,from:data) {
            archive=Array(saved.days.filter{$0.isValid}.suffix(8))
        }
    }
    private func cachedDay(at date: Date, location: ObserverLocation, zone: TimeZone) -> SolarDay {
        if let cached=archive.last(where:{$0.matches(date,location:location,zone:zone)}) { return cached }
        let fresh=CelestialMath.makeDay(date:date,location:location,zone:zone)
        calculationCount+=1;archive.append(fresh);archive=Array(archive.suffix(8))
        if let url=cacheURL {
            do {
                try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
                let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
                try encoder.encode(Archive(days:archive)).write(to:url,options:[.atomic,.completeFileProtectionUnlessOpen])
                cacheWriteCount+=1;cacheError=nil
            } catch { cacheError=error.localizedDescription }
        }
        return fresh
    }
    func state(at date: Date, zone: TimeZone = .autoupdatingCurrent) -> CelestialState? {
        guard let location,location.isValid else { return nil }
        if day?.matches(date,location:location,zone:zone) != true { day=cachedDay(at:date,location:location,zone:zone) }
        guard let day else { return nil }
        return CelestialMath.state(CelestialMath.interpolate(day,time:date.timeIntervalSince1970),at:date.timeIntervalSince1970,location:location,heading:heading)
    }
    func wallpaperBodies(at date: Date, zone: TimeZone, horizontalTangent: Double) -> (sun: SIMD3<Double>,moon: SIMD3<Double>)? {
        guard let day,let location,day.matches(date,location:location,zone:zone) else { return nil }
        let t=date.timeIntervalSince1970
        var progress: Double
        if let rise=day.sunrise,let set=day.sunset,rise<set {
            if t>=rise && t<=set {
                progress=1+(t-rise)/(set-rise) // Return below the horizon by day.
            } else {
                if moonNightSpan.map({t >= $0.start && t < $0.end}) != true {
                    if t<rise {
                        let previous=cachedDay(at:Date(timeIntervalSince1970:day.start-1),location:location,zone:zone)
                        moonNightSpan=previous.sunset.map { ($0,rise) }
                    } else {
                        let next=cachedDay(at:Date(timeIntervalSince1970:day.end),location:location,zone:zone)
                        moonNightSpan=next.sunrise.map { (set,$0) }
                    }
                }
                if let span=moonNightSpan,span.end>span.start { progress=(t-span.start)/(span.end-span.start) }
                else { progress=(t-day.solarNoon)/43200-0.5 }
            }
        } else {
            // No rise/set at polar latitudes: a continuous 24-hour arc with
            // the upper half centered on local solar midnight.
            progress=(t-day.solarNoon)/43200-0.5
        }
        var sun=WallpaperSky.direction(progress:progress+1,horizontalTangent:horizontalTangent)
        var moon=WallpaperSky.direction(progress:progress,horizontalTangent:horizontalTangent)
        if day.daylight == "polarNight" { sun.y = -abs(sun.y) }
        if day.daylight == "polarDay" { sun.y=abs(sun.y);moon.y = -abs(moon.y) }
        return (sun,moon)
    }
    func wallpaperMoon(at date: Date, zone: TimeZone, horizontalTangent: Double) -> SIMD3<Double>? {
        wallpaperBodies(at:date,zone:zone,horizontalTangent:horizontalTangent)?.moon
    }
    static var supportDirectory: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("OceanWallpaper",isDirectory:true)
    }
}
