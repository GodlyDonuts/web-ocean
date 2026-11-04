import Foundation

// Shares the existing IP location. No GPS, key, polling render loop or new timer.
final class WeatherProvider {
    struct Saved:Codable {
        var location:ObserverLocation
        var weather:OceanWeather?
        var measuredAt:Date?
        var fetchedAt:Date?
        var retryAfter:Date
    }
    typealias Fetch=(ObserverLocation,@escaping(Result<(OceanWeather,Date),Error>)->Void)->Void
    private let url:URL
    private let fetch:Fetch
    private var saved:Saved?
    private var requesting=false
    private var generation=0
    private(set) var location:ObserverLocation?
    var onChange:((OceanWeather)->Void)?
    var onStatus:((String)->Void)?
    init(cacheURL:URL=CelestialCycle.supportDirectory.appendingPathComponent("weather.json"),fetch:Fetch?=nil) {
        url=cacheURL;self.fetch=fetch ?? Self.request
        if let data=try? Data(contentsOf:url),let s=try? JSONDecoder().decode(Saved.self,from:data),s.location.isValid,s.weather?.isValid != false { saved=s }
    }
    func setLocation(_ value:ObserverLocation?) {
        guard value?.isValid != false else { return }
        if value != location { generation += 1;requesting=false;location=value }
        refresh()
    }
    func refresh(force:Bool=false,now:Date=Date()) {
        guard let location,!requesting else { return }
        if let s=saved,s.location==location {
            if let w=s.weather,let stamp=s.measuredAt,now.timeIntervalSince(stamp)<86400,now>=stamp { onChange?(w) }
            if !force,let date=s.fetchedAt,now>=date,now.timeIntervalSince(date)<900 { onStatus?("Local weather · Open-Meteo");return }
            if !force,now<s.retryAfter,s.retryAfter.timeIntervalSince(now)<3600 { onStatus?("Using saved weather · retrying later");return }
        }
        requesting=true;let ticket=generation
        saved=Saved(location:location,weather:saved?.location==location ? saved?.weather : nil,measuredAt:saved?.location==location ? saved?.measuredAt : nil,fetchedAt:nil,retryAfter:now.addingTimeInterval(900))
        persist();onStatus?("Updating local weather…")
        fetch(location) { [weak self] result in
            DispatchQueue.main.async {
                guard let self,ticket==self.generation else { return };self.requesting=false
                switch result {
                case .success(let (weather,stamp)):
                    self.saved=Saved(location:location,weather:weather,measuredAt:stamp,fetchedAt:now,retryAfter:now.addingTimeInterval(900))
                    self.persist();self.onChange?(weather);self.onStatus?("Local weather · Open-Meteo")
                case .failure:self.onStatus?("Weather unavailable · keeping current sea")
                }
            }
        }
    }
    private func persist() {
        guard let saved else { return }
        try? FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        if let d=try? JSONEncoder().encode(saved) { try? d.write(to:url,options:.atomic) }
    }
    static func endpoint(_ location:ObserverLocation)->URL {
        var c=URLComponents(string:"https://api.open-meteo.com/v1/forecast")!
        c.queryItems=[URLQueryItem(name:"latitude",value:String(location.latitude)),URLQueryItem(name:"longitude",value:String(location.longitude)),
          URLQueryItem(name:"current",value:"precipitation,rain,showers,weather_code,cloud_cover,wind_speed_10m,wind_direction_10m,wind_gusts_10m"),
          URLQueryItem(name:"wind_speed_unit",value:"ms"),URLQueryItem(name:"timeformat",value:"unixtime"),URLQueryItem(name:"forecast_days",value:"1")]
        return c.url!
    }
    private static func request(_ location:ObserverLocation,completion:@escaping(Result<(OceanWeather,Date),Error>)->Void) {
        let config=URLSessionConfiguration.ephemeral;config.timeoutIntervalForRequest=10;config.timeoutIntervalForResource=15
        config.httpShouldSetCookies=false;config.urlCredentialStorage=nil;config.urlCache=nil
        let session=URLSession(configuration:config)
        session.dataTask(with:endpoint(location)) { data,response,error in
            defer { session.finishTasksAndInvalidate() }
            if let error { completion(.failure(error));return }
            do { completion(.success(try WeatherReply.decode(data ?? Data(),status:(response as? HTTPURLResponse)?.statusCode ?? 0,now:Date()))) }
            catch { completion(.failure(error)) }
        }.resume()
    }
}
