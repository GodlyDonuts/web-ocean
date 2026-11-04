import Foundation
import simd

@main enum CelestialMotionTests {
    static func angle(_ a: SIMD3<Double>,_ b: SIMD3<Double>) -> Double { acos(max(-1,min(1,simd_dot(a,b))))/CelestialMath.rad }
    static func main() throws {
        let iso=ISO8601DateFormatter(),observer=ObserverLocation(latitude:40.7128,longitude:-74.006),zone=TimeZone(identifier:"America/New_York")!
        let cycle=CelestialCycle();cycle.location=observer
        let start=iso.date(from:"2026-10-30T16:00:00Z")!
        var previous: CelestialState?,first: CelestialState?,maximumSunStep=0.0,maximumMoonStep=0.0
        var dayFrames=0,nightFrames=0,sunAbove=0,moonAbove=0
        for minute in 0...1440 {
            let state=cycle.state(at:start.addingTimeInterval(Double(minute)*60),zone:zone)!
            if first==nil { first=state }
            if let previous { maximumSunStep=max(maximumSunStep,angle(previous.apparentSun,state.apparentSun));maximumMoonStep=max(maximumMoonStep,angle(previous.moon,state.moon)) }
            if state.sunAltitude>0 { dayFrames+=1 }
            if state.night>0.99 { nightFrames+=1 }
            if state.apparentSun.y>0 { sunAbove+=1 }
            if state.moon.y>0 { moonAbove+=1 }
            previous=state
        }
        guard maximumSunStep<0.5 && maximumMoonStep<0.5 else {
            fputs("FAIL: direction jump; Sun \(maximumSunStep)°, Moon \(maximumMoonStep)° per minute\n",stderr);exit(1)
        }
        precondition(dayFrames>300 && nightFrames>300 && sunAbove>300 && moonAbove>300)
        precondition(cycle.calculationCount==2 && cycle.cacheWriteCount==0,"Full-day evaluation must only calculate each local day once")
        // Solar direction almost repeats after a solar day, while the Moon
        // advances along its own orbit instead of being locked opposite it.
        precondition(angle(first!.sun,previous!.sun)<1 && angle(first!.moon,previous!.moon)>8)
        let midnight=iso.date(from:"2026-10-31T04:00:00Z")!
        let a=cycle.state(at:midnight.addingTimeInterval(-0.01),zone:zone)!,b=cycle.state(at:midnight.addingTimeInterval(0.01),zone:zone)!
        precondition(angle(a.apparentSun,b.apparentSun)<0.001 && angle(a.moon,b.moon)<0.001)
        let fixtureDefinitions=[("sun_before","2026-10-30T21:15:50Z",270.0,"sun"),("sun_after","2026-10-30T21:45:50Z",270.0,"sun"),("moon_before","2026-10-31T02:10:50Z",60.0,"moon"),("moon_after","2026-10-31T02:40:50Z",60.0,"moon")]
        var fixtures=[[String:Any]]()
        for (name,time,heading,body) in fixtureDefinitions {
            let date=iso.date(from:time)!,s=cycle.state(at:date,zone:zone)!
            let state=CelestialMath.state(CelestialMath.sample(date.timeIntervalSince1970),at:date.timeIntervalSince1970,location:observer,heading:heading)
            let direction=body=="sun" ? state.apparentSun : state.moon
            let pitch = -5.5*CelestialMath.rad,tanY=tan(58*CelestialMath.rad/2),tanX=tanY*1280/800
            let forward=SIMD3(0,sin(pitch),-cos(pitch)),up=SIMD3(0,cos(pitch),sin(pitch)),depth=simd_dot(direction,forward)
            let x=(direction.x/(depth*tanX)+1)*640,y=(1-simd_dot(direction,up)/(depth*tanY))*400
            precondition(depth>0 && (8...1272).contains(x) && (8...792).contains(y))
            fixtures.append(["name":name,"utc":date.timeIntervalSince1970,"heading":heading,"body":body,"anchorUTC":iso.date(from:body=="sun" ? "2026-10-30T21:15:00Z" : "2026-10-31T02:10:00Z")!.timeIntervalSince1970,"verifyFrame":name.hasSuffix("before") ? 8 : 188,"pixel":[x,y],"sunAltitude":s.sunAltitude])
        }
        let report:[String:Any]=["passed":true,"samples":1441,"maximumSunDegreesPerMinute":maximumSunStep,"maximumMoonDegreesPerMinute":maximumMoonStep,"dailyCalculations":cycle.calculationCount,"daySamples":dayFrames,"nightSamples":nightFrames,"fixtures":fixtures]
        let path=CommandLine.arguments.dropFirst().first ?? "macos/build/celestial-motion/trajectory.json"
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path))
        print("PASS: full 24-hour trajectory, continuous sun/Moon directions, independent lunar orbit, local-midnight continuity and daily cache reuse.")
        print("Maximum per-minute movement: Sun \(maximumSunStep)°, Moon \(maximumMoonStep)°.")
    }
}
