import Foundation
import ScreenSaver

// Use the screen-saver framework's own preference domain to cross the saver
// host's sandbox boundary. No sandbox escape, network request or GPS prompt.
enum ScreenSaverEnvironment {
    static let module="local.wallpaper.ocean.screensaver"
    static let wallpaperModule="local.wallpaper.ocean.live"
    struct Saved: Codable, Equatable {
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
        let preview=(UserDefaults.standard.object(forKey:"OceanWeatherPreview") as? NSNumber)?.doubleValue
        let manual=preview.flatMap { $0.isFinite && (0...1).contains($0) ? OceanWeather.storm($0) : nil }
        let saved=Saved(daylightTime:UserDefaults.standard.string(forKey:"OceanDaylightTime") ?? "automatic",
                        location:location?.location,timeZoneID:location?.timeZoneID,
                        weather:manual ?? (matching ? weather?.weather : nil),weatherMeasuredAt:manual != nil ? Date() : (matching ? weather?.measuredAt : nil))
        guard let data=try? JSONEncoder().encode(saved) else { return }
        LiveWallpaperFiles.write(data,name:"environment.json")
        for domain in [module] {
            guard let defaults=ScreenSaverDefaults(forModuleWithName:domain) else { continue }
            defaults.set(data,forKey:"OceanEnvironment");defaults.synchronize()
        }
    }
    static func currentWeather(_ saved:Saved,now:Date=Date())->OceanWeather {
        guard let date=saved.weatherMeasuredAt,let weather=saved.weather,weather.isValid,
              now.timeIntervalSince(date)>=0,now.timeIntervalSince(date)<86400 else { return .fair }
        return weather
    }
    static func read() -> Saved? {
        let domain=Bundle.main.bundleIdentifier==wallpaperModule ? wallpaperModule : module
        guard let defaults=ScreenSaverDefaults(forModuleWithName:domain) else { return nil }
        defaults.synchronize()
        guard let data=defaults.data(forKey:"OceanEnvironment") else { return nil }
        return decode(data)
    }
    static func readLive() -> Saved? {
        guard let data=try? Data(contentsOf:LiveWallpaperFiles.directory.appendingPathComponent("environment.json")) else { return nil }
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
