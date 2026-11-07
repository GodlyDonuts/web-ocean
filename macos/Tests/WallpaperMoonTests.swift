import Foundation
import simd

@main enum WallpaperMoonTests {
    static let zone=TimeZone(identifier:"America/New_York")!
    static let location=ObserverLocation(latitude:40.7128,longitude:-74.006)
    static func date(_ s: String) -> Date { ISO8601DateFormatter().date(from:s)! }
    static func main() throws {
        let cycle=CelestialCycle();cycle.location=location
        let evening=date("2026-10-31T00:00:00Z")
        _=cycle.state(at:evening,zone:zone)
        let set=cycle.day!.sunset!
        let following=CelestialMath.makeDay(date:Date(timeIntervalSince1970:cycle.day!.end),location:location,zone:zone)
        let rise=following.sunrise!
        var fixtures=[[String:Any]]()
        for step in 0...240 {
            let t=set+(rise-set)*Double(step)/240
            let when=Date(timeIntervalSince1970:t),state=cycle.state(at:when,zone:zone)!
            for aspect in [0.5,1.6,2.4] {
                let tanY=tan(29*CelestialMath.rad),moon=cycle.wallpaperMoon(at:when,zone:zone,horizontalTangent:tanY*aspect)!
                let pitch = -5.5*CelestialMath.rad
                let forward=SIMD3(0,sin(pitch),-cos(pitch)),up=SIMD3(0,cos(pitch),sin(pitch))
                let depth=simd_dot(moon,forward)
                precondition(depth>0 && abs(moon.x/(depth*tanY*aspect))<0.85 && abs(simd_dot(moon,up)/(depth*tanY))<0.9)
                precondition(moon.y >= -1e-10 && abs(simd_length(moon)-1)<1e-10)
                let light=WallpaperMoon.phaseLight(state:state,displayedMoon:moon)
                precondition(abs(simd_length(light)-1)<1e-10)
                precondition(abs((1-simd_dot(moon,light))/2-state.moonIllumination)<1e-10)
            }
        }
        precondition(cycle.calculationCount==2 && cycle.cacheWriteCount==0,"Night uses two cached solar days, no frame-loop ephemeris calls")
        for boundary in [set,rise] {
            var positions=[SIMD3<Double>]()
            for delta in [-0.01,0.01] {
                let d=Date(timeIntervalSince1970:boundary+delta);_=cycle.state(at:d,zone:zone)
                positions.append(cycle.wallpaperMoon(at:d,zone:zone,horizontalTangent:0.9)!)
            }
            precondition(simd_distance(positions[0],positions[1])<0.00001,"No sunset/sunrise jump")
        }
        let midnight=date("2026-10-31T04:00:00Z")
        var adjacent=[SIMD3<Double>]()
        for dt in [-0.01,0.01] {
            let d=midnight.addingTimeInterval(dt);_=cycle.state(at:d,zone:zone)
            adjacent.append(cycle.wallpaperMoon(at:d,zone:zone,horizontalTangent:tan(29*CelestialMath.rad)*1.6)!)
        }
        precondition(simd_distance(adjacent[0],adjacent[1])<0.00001,"No midnight jump")
        let before=cycle.calculationCount
        let clock=Date();var checksum=0.0
        for _ in 0..<10000 { checksum+=cycle.wallpaperMoon(at:midnight,zone:zone,horizontalTangent:0.9)!.y }
        let cachedMicroseconds=Date().timeIntervalSince(clock)*1e6/10000
        precondition(checksum>0)
        precondition(cycle.calculationCount==before)
        // Independent published calendar phases: new, waxing quarter, full,
        // waning quarter. Position changes must preserve illuminated fraction
        // AND the real bright-limb orientation, including waxing/waning.
        // Calendar: https://eclipse.gsfc.nasa.gov/phase/phase2001gmt.html
        // Fixtures use nearby local nights rather than the event minute.
        for (name,stamp,expected) in [("new","2024-04-09T03:00:00Z",0.0),("waxing_quarter","2024-04-16T03:00:00Z",0.5),("full","2024-04-24T03:00:00Z",1.0),("waning_quarter","2024-05-01T03:00:00Z",0.5)] {
            let d=date(stamp),s=cycle.state(at:d,zone:zone)!
            let moon=cycle.wallpaperMoon(at:d,zone:zone,horizontalTangent:tan(29*CelestialMath.rad)*1.6)!
            let light=WallpaperMoon.phaseLight(state:s,displayedMoon:moon)
            precondition(abs(s.moonIllumination-expected)<0.07)
            let (a,b)=WallpaperMoon.diskAxes(s.moon),(x,y)=WallpaperMoon.diskAxes(moon)
            let old=simd_normalize(SIMD2(simd_dot(s.sun,a),simd_dot(s.sun,b)))
            let new=simd_normalize(SIMD2(simd_dot(light,x),simd_dot(light,y)))
            precondition(simd_dot(old,new)>0.999999)
            fixtures.append(["name":name,"utc":d.timeIntervalSince1970,"direction":[moon.x,moon.y,moon.z],"phaseLight":[light.x,light.y,light.z],"illuminatedFraction":s.moonIllumination])
        }
        // Reuse one night across the DST rollback; absolute UTC stays smooth.
        var dstPositions=[SIMD3<Double>]()
        for stamp in ["2026-11-01T05:59:59Z","2026-11-01T06:00:01Z"] {
            let d=date(stamp);_=cycle.state(at:d,zone:zone)
            let position=cycle.wallpaperMoon(at:d,zone:zone,horizontalTangent:0.9)!
            precondition(position.y>0);dstPositions.append(position)
        }
        precondition(simd_distance(dstPositions[0],dstPositions[1])<0.001,"No DST rollback jump")
        for latitude in [-89.0,89.0] {
            let polar=CelestialCycle();polar.location=ObserverLocation(latitude:latitude,longitude:0)
            let d=date("2026-12-21T00:00:00Z");_=polar.state(at:d,zone:zone)
            let p=polar.wallpaperMoon(at:d,zone:zone,horizontalTangent:0.9)!
            precondition(p.x.isFinite && p.y.isFinite && p.z.isFinite && abs(simd_length(p)-1)<1e-10)
        }
        // Two points of the default path for actual GPU disk-motion checks.
        for (name,stamp) in [("arc_before","2026-10-31T00:00:50Z"),("arc_after","2026-10-31T00:30:50Z")] {
            let d=date(stamp),s=cycle.state(at:d,zone:zone)!
            let moon=cycle.wallpaperMoon(at:d,zone:zone,horizontalTangent:tan(29*CelestialMath.rad)*1.6)!
            fixtures.append(["name":name,"utc":d.timeIntervalSince1970,"direction":[moon.x,moon.y,moon.z],"illuminatedFraction":s.moonIllumination])
        }
        try JSONSerialization.data(withJSONObject:["passed":true,"fixtures":fixtures,"cachedArcMicroseconds":cachedMicroseconds],options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:"macos/build/unit/wallpaper-moon.json"))
        print("PASS: visible sunset-to-sunrise arc in three aspects, midnight/DST continuity, cached night bounds, real phases/bright limbs and finite polar fallback")
        print("Cached arc: \(cachedMicroseconds) µs; 10,000 updates caused no additional solar calculations or cache writes")
    }
}
