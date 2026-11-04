import Foundation
import simd

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
    static let version = 2
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
    let lunarShadow: SIMD3<Double> // centre of Earth's shadow, offset like the apparent Moon
    let solarObscuration: Double // fraction of the solar disk covered by the Moon
    let lunarUmbra: Double // fraction of the lunar disk inside Earth's umbra
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
        let moon=lunar(d+69.0/86400) // Delta T: the lunar theory runs in terrestrial time
        return EquatorialSample(time:time,sun:sun,moon:equatorial(longitude:moon.longitude,latitude:moon.latitude,obliquity:e),sunDistanceAU:1.00014-0.01671*cos(g)-0.00014*cos(2*g),moonDistanceKm:moon.distance)
    }
    // Leading periodic terms of Meeus' lunar theory (Astronomical Algorithms ch. 47):
    // (coefficient, D, M, M', F). About 0.01 degrees, enough to place real eclipses.
    static let lunarLongitude: [(Double,Double,Double,Double,Double)] = [
        (6.288774,0,0,1,0),(1.274027,2,0,-1,0),(0.658314,2,0,0,0),(0.213618,0,0,2,0),(-0.185116,0,1,0,0),(-0.114332,0,0,0,2),
        (0.058793,2,0,-2,0),(0.057066,2,-1,-1,0),(0.053322,2,0,1,0),(0.045758,2,-1,0,0),(-0.040923,0,1,-1,0),(-0.034720,1,0,0,0),
        (-0.030383,0,1,1,0),(0.015327,2,0,0,-2),(-0.012528,0,0,1,2),(0.010980,0,0,1,-2),(0.010675,4,0,-1,0),(0.010034,0,0,3,0),
        (0.008548,4,0,-2,0),(-0.007888,2,1,-1,0),(-0.006766,2,1,0,0),(-0.005163,1,0,-1,0),(0.004987,1,1,0,0),(0.004036,2,-1,1,0)]
    static let lunarLatitude: [(Double,Double,Double,Double,Double)] = [
        (5.128122,0,0,0,1),(0.280602,0,0,1,1),(0.277693,0,0,1,-1),(0.173237,2,0,0,-1),(0.055413,2,0,-1,1),(0.046271,2,0,-1,-1),
        (0.032573,2,0,0,1),(0.017198,0,0,2,1),(0.009266,2,0,1,-1),(0.008822,0,0,2,-1),(0.008216,2,-1,0,-1),(0.004324,2,0,-2,-1),(0.004200,2,0,1,1)]
    static let lunarDistance: [(Double,Double,Double,Double,Double)] = [
        (-20905.355,0,0,1,0),(-3699.111,2,0,-1,0),(-2955.968,2,0,0,0),(-569.925,0,0,2,0),(48.888,0,1,0,0),(-3.149,0,0,0,2),
        (246.158,2,0,-2,0),(-152.138,2,-1,-1,0),(-170.733,2,0,1,0),(-204.586,2,-1,0,0),(-129.620,0,1,-1,0),(108.743,1,0,0,0),
        (104.755,0,1,1,0),(10.321,2,0,0,-2),(79.661,0,0,1,-2),(-34.782,4,0,-1,0),(-23.210,0,0,3,0),(-21.636,4,0,-2,0),
        (24.208,2,1,-1,0),(30.824,2,1,0,0),(-8.379,1,0,-1,0),(-16.675,1,1,0,0),(-12.831,2,-1,1,0)]
    static func lunar(_ d: Double) -> (longitude: Double, latitude: Double, distance: Double) {
        let D=radians(297.8502+12.19074912*d),M=radians(357.5291+0.98560028*d)
        let Mp=radians(134.9634+13.06499295*d),F=radians(93.2721+13.22935024*d)
        func arg(_ t: (Double,Double,Double,Double,Double)) -> Double { t.1*D+t.2*M+t.3*Mp+t.4*F }
        let l=lunarLongitude.reduce(218.3165+13.17639648*d) { $0+$1.0*sin(arg($1)) }
        let b=lunarLatitude.reduce(0.0) { $0+$1.0*sin(arg($1)) }
        let r=lunarDistance.reduce(385000.56) { $0+$1.0*cos(arg($1)) }
        return (radians(l),b*rad,r)
    }
    static func separation(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        atan2(simd_length(simd_cross(a,b)),simd_dot(a,b))
    }
    /// Area shared by two disks of angular radii r1, r2 whose centres are d apart.
    static func overlap(_ r1: Double, _ r2: Double, _ d: Double) -> Double {
        if d>=r1+r2 { return 0 }
        if d<=abs(r1-r2) { let r=min(r1,r2); return Double.pi*r*r }
        let a=r1*r1*acos(max(-1,min(1,(d*d+r1*r1-r2*r2)/(2*d*r1))))
        let b=r2*r2*acos(max(-1,min(1,(d*d+r2*r2-r1*r1)/(2*d*r2))))
        return a+b-0.5*sqrt(max(0,(-d+r1+r2)*(d+r1-r2)*(d-r1+r2)*(d+r1+r2)))
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
        let sun=basis*s.sun,topocentric=basis*s.moon*s.moonDistanceKm-SIMD3(0,6378.137,0),moon=simd_normalize(topocentric)
        let sunRadius=0.2666/s.sunDistanceAU*rad,moonRadius=asin(1737.4/simd_length(topocentric))
        let shadow=simd_normalize(-sun*s.moonDistanceKm-SIMD3(0,6378.137,0)),apparentMoon=refracted(moon)
        let umbra=1.02*asin(6378.137/s.moonDistanceKm)-sunRadius
        let obscured=overlap(sunRadius,moonRadius,separation(sun,moon))/(Double.pi*sunRadius*sunRadius)
        let umbral=overlap(moonRadius,umbra,separation(shadow,moon))/(Double.pi*moonRadius*moonRadius)
        let phase=max(0,min(1,(1-simd_dot(s.sun,s.moon))*0.5))
        let altitude=asin(max(-1,min(1,sun.y)))/rad
        return CelestialState(skyBasis:basis,sun:sun,apparentSun:refracted(sun),moon:apparentMoon,moonIllumination:phase,sunRadius:sunRadius,moonRadius:moonRadius,sunAltitude:altitude,night:1-smooth(-12,-3,altitude),lunarShadow:simd_normalize(apparentMoon+shadow-moon),solarObscuration:min(1,obscured),lunarUmbra:min(1,umbral))
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
    var location: ObserverLocation? { didSet { if oldValue != location { day=nil } } }
    var heading=270.0 // geographic west, fixed view; camera does not chase the sun
    init(cacheURL: URL? = nil) {
        self.cacheURL=cacheURL
        if let url=cacheURL,let data=try? Data(contentsOf:url),let saved=try? JSONDecoder().decode(Archive.self,from:data) {
            archive=Array(saved.days.filter{$0.isValid}.suffix(8))
        }
    }
    func state(at date: Date, zone: TimeZone = .autoupdatingCurrent) -> CelestialState? {
        guard let location,location.isValid else { return nil }
        if day?.matches(date,location:location,zone:zone) != true {
            day=archive.last(where:{$0.matches(date,location:location,zone:zone)})
            if day == nil {
                let fresh=CelestialMath.makeDay(date:date,location:location,zone:zone)
                day=fresh;calculationCount+=1;archive.append(fresh);archive=Array(archive.suffix(8))
                if let url=cacheURL {
                    do {
                        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
                        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
                        try encoder.encode(Archive(days:archive)).write(to:url,options:[.atomic,.completeFileProtectionUnlessOpen])
                        cacheWriteCount+=1;cacheError=nil
                    } catch { cacheError=error.localizedDescription }
                }
            }
        }
        guard let day else { return nil }
        return CelestialMath.state(CelestialMath.interpolate(day,time:date.timeIntervalSince1970),at:date.timeIntervalSince1970,location:location,heading:heading)
    }
    static var supportDirectory: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("OceanWallpaper",isDirectory:true)
    }
}
