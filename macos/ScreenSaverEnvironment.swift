import Foundation
import ScreenSaver

// Use the screen-saver framework's own preference domain to cross the saver
// host's sandbox boundary. No sandbox escape, network request or GPS prompt.
enum ScreenSaverEnvironment {
    static let module="local.wallpaper.ocean.screensaver"
    struct Saved: Codable {
        var daylightTime: String
        var location: ObserverLocation?
        var timeZoneID: String?
        var weather: OceanWeather?
        var weatherMeasuredAt: Date?
    }
    static func publishFromApp() {
        let directory=CelestialCycle.supportDirectory
        let location=(try? Data(contentsOf:directory.appendingPathComponent("ip-location.json")))
            .flatMap { try? JSONDecoder().decode(ObserverLocationProvider.SavedLocation.self,from:$0) }
        let weather=(try? Data(contentsOf:directory.appendingPathComponent("weather.json")))
            .flatMap { try? JSONDecoder().decode(WeatherProvider.Saved.self,from:$0) }
        let matching=weather?.location==location?.location
        let saved=Saved(daylightTime:UserDefaults.standard.string(forKey:"OceanDaylightTime") ?? "automatic",
                        location:location?.location,timeZoneID:location?.timeZoneID,
                        weather:matching ? weather?.weather : nil,weatherMeasuredAt:matching ? weather?.measuredAt : nil)
        guard let data=try? JSONEncoder().encode(saved),let defaults=ScreenSaverDefaults(forModuleWithName:module) else { return }
        defaults.set(data,forKey:"OceanEnvironment");defaults.synchronize()
    }
    static func read() -> Saved? {
        guard let defaults=ScreenSaverDefaults(forModuleWithName:module) else { return nil }
        defaults.synchronize()
        guard let data=defaults.data(forKey:"OceanEnvironment") else { return nil }
        return decode(data)
    }
    static func decode(_ data: Data) -> Saved? {
        guard data.count<=65536,let saved=try? JSONDecoder().decode(Saved.self,from:data),
              saved.location?.isValid != false,DaylightTime(value:saved.daylightTime) != nil,
              saved.timeZoneID==nil || saved.timeZoneID.flatMap(TimeZone.init(identifier:)) != nil,
              saved.weather?.isValid != false else { return nil }
        return saved
    }
}
