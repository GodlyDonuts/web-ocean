import Foundation

@main enum IPLocationTests {
    static func pump(_ predicate: ()->Bool) {
        let end=Date().addingTimeInterval(2)
        while !predicate() && Date()<end { RunLoop.main.run(until:Date().addingTimeInterval(0.005)) }
        precondition(predicate())
    }
    static func main() throws {
        let data=Data(#"{"success":true,"latitude":40.7128,"longitude":-74.006,"timezone":{"id":"America/New_York"}}"#.utf8)
        let (location,zone)=try IPLocationReply.location(from:data,status:200)
        precondition(location==ObserverLocation(latitude:40.71,longitude:-74.01))
        for (body,status) in [(#"{"success":false}"#,200),(#"{"success":true,"latitude":91,"longitude":0,"timezone":{"id":"UTC"}}"#,200),(#"{"success":true,"latitude":0,"longitude":0,"timezone":{"id":"Invalid/Zone"}}"#,200),("garbage",200),(String(decoding:data,as:UTF8.self),429)] {
            do { _=try IPLocationReply.location(from:Data(body.utf8),status:status);preconditionFailure("Invalid response accepted") } catch { }
        }
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let cache=directory.appendingPathComponent("ip.json")
        var requests=0,changes=0
        var complete: ((Result<(ObserverLocation,TimeZone),Error>)->Void)?
        let provider=ObserverLocationProvider(cacheURL:cache,lookup:{ callback in requests+=1;complete=callback })
        provider.onChange={ _,_ in changes+=1 }
        let now=Date(timeIntervalSince1970:1793354400)
        provider.refresh(now:now);provider.refresh(now:now);precondition(requests==1)
        complete?(.success((location,zone)));pump{changes==1}
        for _ in 0..<10000 { provider.refresh(now:now.addingTimeInterval(3600)) }
        precondition(requests==1 && provider.location==location && provider.timeZone==zone)
        let reload=ObserverLocationProvider(cacheURL:cache,lookup:{ _ in requests+=1 })
        reload.refresh(now:now.addingTimeInterval(7200));precondition(requests==1 && reload.location==location)
        changes=0;provider.refresh(now:now.addingTimeInterval(86401));precondition(requests==2)
        complete?(.failure(IPLocationReply.Failure.invalidResponse));pump{changes==1}
        provider.refresh(now:now.addingTimeInterval(86500));precondition(requests==2 && provider.location==location)
        provider.refresh(force:true,now:now.addingTimeInterval(86501));precondition(requests==3)
        complete?(.success((location,zone)));pump{changes>1}
        let text=try String(contentsOf:cache,encoding:.utf8)
        precondition(!text.contains("\"ip\"") && !text.contains("publicIP"))
        print("PASS: IP response validation, coordinate rounding/timezone, one lookup across 10,000 cached refreshes, restart persistence, 24 h expiry, failure backoff, saved-location fallback and manual refresh. No live network request.")
    }
}
