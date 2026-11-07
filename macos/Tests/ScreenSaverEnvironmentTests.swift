import Foundation
@main struct ScreenSaverEnvironmentTests {
 static func main() throws {
    var saved=ScreenSaverEnvironment.Saved(daylightTime:"sunset",location:ObserverLocation(latitude:40.71,longitude:-74.01),timeZoneID:"America/New_York",weather:nil,weatherMeasuredAt:nil)
    func data() -> Data { try! JSONEncoder().encode(saved) }
    precondition(ScreenSaverEnvironment.decode(data())?.daylightTime=="sunset")
    saved.location=ObserverLocation(latitude:999,longitude:0)
    precondition(ScreenSaverEnvironment.decode(data())==nil)
    saved.location=nil;saved.timeZoneID="invalid-zone"
    precondition(ScreenSaverEnvironment.decode(data())==nil)
    saved.timeZoneID=nil;saved.daylightTime="28:01"
    precondition(ScreenSaverEnvironment.decode(data())==nil)
    precondition(ScreenSaverEnvironment.decode(Data("broken".utf8))==nil)
    precondition(ScreenSaverEnvironment.decode(Data(repeating:0,count:65537))==nil)
    print("PASS: shared saver environment encoding, corrupt/oversized payloads, invalid location/timezone/daylight; no OS writes")
 }
}
