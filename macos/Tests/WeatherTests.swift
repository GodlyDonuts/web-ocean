import Foundation
@main struct WeatherTests {
 static func main() throws {
    var dynamics=WeatherDynamics(.storm(0));dynamics.setTarget(.storm(1))
    var previous=dynamics.current
    for _ in 0..<18000 {
        dynamics.advance(1/30)
        let current=dynamics.current
        precondition(current.isValid)
        precondition(abs(current.rain-previous.rain)<0.005 && abs(current.wind-previous.wind)<0.05)
        previous=current
    }
    precondition(dynamics.current.rain>0.999 && dynamics.current.wind>44.9)
    dynamics.setTarget(.storm(0.08))
    for _ in 0..<18000 { dynamics.advance(1/30);precondition(dynamics.current.isValid) }
    precondition(abs(dynamics.current.rain-0.08)<0.00001)
    // Frame-rate independent closed form, target reversal with continuous value.
    var a=WeatherDynamics(),b=WeatherDynamics();a.setTarget(.storm(1));b.setTarget(.storm(1))
    for _ in 0..<300 { a.advance(1/30) };b.advance(10)
    for (x,y) in zip(a.current.values,b.current.values) { precondition(abs(x-y)<1e-9) }
    let before=a.current;a.setTarget(.storm(0));precondition(a.current==before)
    for i in 0..<10000 { if i%13==0 { a.setTarget(.storm(Double(i%101)/100)) };a.advance(1/60);precondition(a.current.isValid) }
    var north=OceanWeather.fair;north.direction=359
    var turning=WeatherDynamics(north);north.direction=1;turning.setTarget(north);turning.advance(1)
    precondition(turning.current.direction>359 || turning.current.direction<1)
    let now=Date(timeIntervalSince1970:1793394900)
    let raw=#"{"current":{"time":1793394900,"interval":900,"precipitation":2,"rain":1,"showers":1,"weather_code":95,"cloud_cover":100,"wind_speed_10m":20,"wind_direction_10m":270,"wind_gusts_10m":40}}"#.data(using:.utf8)!
    let (weather,_)=try WeatherReply.decode(raw,status:200,now:now)
    precondition(abs(weather.rain-(1-exp(-8.0/18)))<1e-12)
    precondition(weather.thunder>=0.45 && abs(weather.wind-28.8)<1e-10 && weather.direction==90)
    do { _=try WeatherReply.decode(raw,status:500,now:now);preconditionFailure() } catch {}
    do { _=try WeatherReply.decode(raw,status:200,now:now.addingTimeInterval(9000));preconditionFailure() } catch {}
    let peak=WeatherLightning.peakTime()
    precondition(WeatherLightning.flash(time:peak,thunder:1)>0.2)
    precondition(WeatherLightning.flash(time:peak,thunder:0)==0)
    precondition(abs(WeatherLightning.flash(time:peak,thunder:1)-WeatherLightning.flash(time:peak+53248,thunder:1))<1e-9)
    precondition(WeatherLightning.flash(time:0,thunder:1)==0)
    print("LIGHTNING_FIXTURE: \(peak)")
    print("PASS: hurricane→drizzle, bounded per-frame changes, interrupted transitions, frame-rate independence, shortest wind turn, validated weather units/age/status.")
 }
}
