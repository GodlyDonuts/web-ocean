import Foundation

struct IPLocationReply: Decodable {
    struct Zone: Decodable { let id: String }
    let success: Bool
    let latitude: Double?
    let longitude: Double?
    let timezone: Zone?
    static func location(from data: Data, status: Int) throws -> (ObserverLocation,TimeZone) {
        guard status==200,data.count<=131072 else { throw Failure.invalidResponse }
        let reply=try JSONDecoder().decode(Self.self,from:data)
        guard reply.success,let lat=reply.latitude,let lon=reply.longitude,
              let id=reply.timezone?.id,let zone=TimeZone(identifier:id) else { throw Failure.invalidResponse }
        guard ObserverLocation(latitude:lat,longitude:lon).isValid else { throw Failure.invalidResponse }
        let location=ObserverLocation(latitude:(lat*100).rounded()/100,longitude:(lon*100).rounded()/100)
        guard location.isValid else { throw Failure.invalidResponse }
        return (location,zone)
    }
    enum Failure: Error { case invalidResponse }
}

// Coarse IP geolocation, at most daily unless the user explicitly refreshes.
// Stores only rounded coordinates/timezone/timestamps, never the public IP.
// All solar/lunar calculations happen locally. No OS location permission/GPS.
final class ObserverLocationProvider {
    struct SavedLocation: Codable {
        let location: ObserverLocation?
        let timeZoneID: String?
        let measuredAt: Date?
        let retryAfter: Date
    }
    typealias Lookup = (@escaping (Result<(ObserverLocation,TimeZone),Error>)->Void)->Void
    private let url: URL
    private let lookup: Lookup
    private var saved: SavedLocation?
    private var requesting=false
    var onChange: ((ObserverLocation?,TimeZone?)->Void)?
    var onStatus: ((String)->Void)?
    private(set) var status="Finding approximate location from your IP…"
    var location: ObserverLocation? { saved?.location }
    var timeZone: TimeZone? { saved?.timeZoneID.flatMap(TimeZone.init(identifier:)) }
    init(cacheURL: URL = CelestialCycle.supportDirectory.appendingPathComponent("ip-location.json"),lookup: Lookup? = nil) {
        url=cacheURL;self.lookup=lookup ?? Self.fetch
        if let data=try? Data(contentsOf:url),let value=try? JSONDecoder().decode(SavedLocation.self,from:data),value.location?.isValid != false,value.timeZoneID.flatMap(TimeZone.init(identifier:)) != nil || value.location==nil { saved=value }
    }
    func refresh(force: Bool = false, now: Date = Date()) {
        guard !requesting else { return }
        if let saved,let measured=saved.measuredAt,!force,now>=measured,now.timeIntervalSince(measured)<86400 {
            updateStatus("Daylight follows your approximate IP location");onChange?(location,timeZone);return
        }
        if !force,let saved,now<saved.retryAfter,saved.retryAfter.timeIntervalSince(now)<86400 {
            onChange?(location,timeZone)
            updateStatus(location==nil ? "Location lookup unavailable; retry later" : "Using saved IP location while offline")
            return
        }
        requesting=true
        saved=SavedLocation(location:location,timeZoneID:timeZone?.identifier,measuredAt:saved?.measuredAt,retryAfter:now.addingTimeInterval(900))
        persist()
        updateStatus("Finding approximate location from your IP…")
        lookup { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requesting=false
                switch result {
                case .success(let (location,zone)):
                    self.saved=SavedLocation(location:location,timeZoneID:zone.identifier,measuredAt:now,retryAfter:now.addingTimeInterval(86400))
                    self.persist();self.onChange?(location,zone)
                    self.updateStatus("Daylight follows your approximate IP location")
                case .failure:
                    self.onChange?(self.location,self.timeZone)
                    self.updateStatus(self.location==nil ? "Location lookup unavailable; retry from Daylight" : "Using saved IP location while offline")
                }
            }
        }
    }
    private func persist() {
        guard let saved else { return }
        do {
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(saved).write(to:url,options:.atomic)
        } catch { /* Continue using in-memory state; never block the renderer. */ }
    }
    private func updateStatus(_ value: String) { status=value;onStatus?(value) }
    private static func fetch(completion: @escaping (Result<(ObserverLocation,TimeZone),Error>)->Void) {
        let configuration=URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest=10;configuration.timeoutIntervalForResource=15
        configuration.httpShouldSetCookies=false;configuration.urlCredentialStorage=nil;configuration.urlCache=nil
        let session=URLSession(configuration:configuration)
        // Omitting an IP makes the service resolve the request's public IP.
        let endpoint=URL(string:"https://ipwho.is/?fields=success,latitude,longitude,timezone.id")!
        var request=URLRequest(url:endpoint);request.setValue("application/json",forHTTPHeaderField:"Accept")
        session.dataTask(with:request) { data,response,error in
            defer { session.finishTasksAndInvalidate() }
            if let error { completion(.failure(error));return }
            do {
                let result=try IPLocationReply.location(from:data ?? Data(),status:(response as? HTTPURLResponse)?.statusCode ?? 0)
                completion(.success(result))
            } catch { completion(.failure(error)) }
        }.resume()
    }
}
