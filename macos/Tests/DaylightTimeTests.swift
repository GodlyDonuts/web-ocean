import Foundation

@main enum DaylightTimeTests {
    static func main() throws {
        let zone=TimeZone(identifier:"America/New_York")!,location=ObserverLocation(latitude:40.7128,longitude:-74.006)
        let iso=ISO8601DateFormatter(),reference=iso.date(from:"2026-10-30T16:00:00Z")!
        let day=CelestialMath.makeDay(date:reference,location:location,zone:zone)
        for mode in DaylightTime.Mode.allCases where mode != .custom {
            let t=DaylightTime(mode:mode);precondition(DaylightTime(value:t.value)==t)
        }
        for value in ["00:00","06:30","18:45","23:59"] {
            let t=DaylightTime(value:value)!,date=t.date(reference:reference,day:day,zone:zone)!
            var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone
            let parts=calendar.dateComponents([.hour,.minute],from:date)
            precondition(parts.hour!*60+parts.minute! == t.minutes && DaylightTime(value:t.value)==t)
            precondition(day.matches(date,location:location,zone:zone))
        }
        for value in ["custom","24:00","12:60","-1:30","1:30","12:3","12:30:00","NaN",":","１２:３０"] { precondition(DaylightTime(value:value)==nil) }
        precondition(DaylightTime().date(reference:reference,day:day,zone:zone)==reference)
        precondition(DaylightTime(mode:.sunrise).date(reference:reference,day:day,zone:zone)!.timeIntervalSince1970==day.sunrise!)
        precondition(DaylightTime(mode:.sunset).date(reference:reference,day:day,zone:zone)!.timeIntervalSince1970==day.sunset!)
        precondition(DaylightTime(mode:.goldenHour).date(reference:reference,day:day,zone:zone)!.timeIntervalSince1970==day.sunset!-2700)
        precondition(DaylightTime(mode:.midday).date(reference:reference,day:day,zone:zone)!.timeIntervalSince1970==day.solarNoon)
        // Holding a clock time remains local across DST gaps/repeated hours.
        for stamp in ["2026-03-08T16:00:00Z","2026-11-01T16:00:00Z"] {
            let d=iso.date(from:stamp)!,solar=CelestialMath.makeDay(date:d,location:location,zone:zone)
            for value in ["01:30","02:30","18:30"] {
                let selected=DaylightTime(value:value)!.date(reference:d,day:solar,zone:zone)!
                precondition(solar.matches(selected,location:location,zone:zone))
            }
        }
        let tomorrow=CelestialMath.makeDay(date:reference.addingTimeInterval(86400),location:location,zone:zone)
        precondition(DaylightTime(mode:.sunset).date(reference:reference,day:day,zone:zone) != DaylightTime(mode:.sunset).date(reference:reference.addingTimeInterval(86400),day:tomorrow,zone:zone))
        let polar=CelestialMath.makeDay(date:reference,location:ObserverLocation(latitude:89,longitude:0),zone:zone)
        precondition(DaylightTime(mode:.sunset).date(reference:reference,day:polar,zone:zone)==nil)
        print("PASS: daylight presets/custom times, persisted value roundtrip, local timezone/DST, daily refresh and unavailable polar events")
    }
}
