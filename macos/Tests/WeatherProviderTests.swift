import Foundation
@main struct WeatherProviderTests {
 static func pump(_ condition:()->Bool) {
    let end=Date().addingTimeInterval(3)
    while !condition() && Date()<end { RunLoop.main.run(until:Date().addingTimeInterval(0.005)) }
    precondition(condition())
 }
 static func main() throws {
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:directory) }
    let url=directory.appendingPathComponent("weather.json")
    let a=ObserverLocation(latitude:40.71,longitude:-74.01),b=ObserverLocation(latitude:51.5,longitude:-0.12)
    var callbacks=[(Result<(OceanWeather,Date),Error>)->Void]()
    var changes=[OceanWeather]();var calls=0;var status=""
    let provider=WeatherProvider(cacheURL:url,fetch:{ _,completion in calls+=1;callbacks.append(completion) })
    provider.onChange={ changes.append($0) };provider.onStatus={ status=$0 }
    provider.setLocation(a);precondition(calls==1)
    for _ in 0..<100 { provider.refresh() };precondition(calls==1)
    callbacks.removeFirst()(.success((.storm(1),Date())));pump { changes.count==1 }
    for _ in 0..<100 { provider.refresh() };precondition(calls==1)
    let restored=WeatherProvider(cacheURL:url,fetch:{ _,_ in preconditionFailure("Fresh cache must prevent fetch") })
    var cached:OceanWeather?;restored.onChange={ cached=$0 };restored.setLocation(a);precondition(cached == .storm(1))
    provider.refresh(now:Date().addingTimeInterval(901));precondition(calls==2)
    callbacks.removeFirst()(.failure(WeatherReply.Failure.invalid));pump { status.hasPrefix("Weather unavailable") }
    precondition(changes.last == .storm(1))
    provider.refresh(now:Date().addingTimeInterval(902));precondition(calls==2)
    // Move while a request is in flight; old-location result must be discarded.
    provider.setLocation(b);precondition(calls==3)
    provider.setLocation(a);precondition(calls==4)
    let count=changes.count
    callbacks.removeFirst()(.success((.storm(0.9),Date())))
    RunLoop.main.run(until:Date().addingTimeInterval(0.02));precondition(changes.count==count)
    callbacks.removeFirst()(.success((.storm(0.08),Date())));pump { changes.last == .storm(0.08) }
    let corruptURL=directory.appendingPathComponent("corrupt.json")
    try Data("broken".utf8).write(to:corruptURL)
    var recovered=false
    let corrupt=WeatherProvider(cacheURL:corruptURL,fetch:{ _,_ in recovered=true })
    corrupt.setLocation(a);precondition(recovered)
    let staleURL=directory.appendingPathComponent("stale.json")
    let stale=WeatherProvider.Saved(location:a,weather:.storm(1),measuredAt:Date().addingTimeInterval(-90000),fetchedAt:Date().addingTimeInterval(-90000),retryAfter:Date.distantPast)
    try JSONEncoder().encode(stale).write(to:staleURL)
    var staleReapplied=false;var staleFetched=false
    let expired=WeatherProvider(cacheURL:staleURL,fetch:{ _,_ in staleFetched=true })
    expired.onChange={ _ in staleReapplied=true };expired.setLocation(a)
    precondition(!staleReapplied && staleFetched)
    let endpoint=WeatherProvider.endpoint(a).absoluteString
    precondition(endpoint.hasPrefix("https://api.open-meteo.com/") && endpoint.contains("wind_speed_unit=ms") && !endpoint.contains("apikey"))
    if CommandLine.arguments.count>1 {
        let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
        let (w,_)=try WeatherReply.decode(data,status:200,now:Date());precondition(w.isValid)
        print("PASS: actual HTTPS weather response parsed and normalized.")
    }
    print("PASS: request coalescing, 15-minute cache, restart recovery, failure retention/backoff, corrupt/expired-cache recovery, stale-location race rejection, HTTPS/unit policy; no real network in fixtures.")
 }
}
