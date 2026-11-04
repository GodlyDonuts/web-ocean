import Foundation
import simd

// Values are continuous, independently controlled meteorological inputs.
struct OceanWeather: Codable, Equatable {
    var rain: Double // normalized optical rain density, 0...1
    var cloud: Double
    var wind: Double // m/s, bounded for the visual ocean model
    var direction: Double // degrees toward, in scene coordinates
    var thunder: Double
    var mist: Double
    var severity: Double { max(rain*0.75,min(1,max(0,(wind-10)/35))) }
    static let fair = OceanWeather(rain:0,cloud:0.4,wind:7,direction:118,thunder:0,mist:0)
    static func storm(_ amount: Double) -> OceanWeather {
        let t=max(0,min(1,amount))
        return OceanWeather(rain:t,cloud:0.4+0.6*sqrt(t),wind:7+38*pow(t,1.3),direction:118,
                            thunder:max(0,(t-0.55)/0.45),mist:t*0.85)
    }
    var isValid: Bool {
        [rain,cloud,wind,direction,thunder,mist].allSatisfy(\.isFinite) &&
        (0...1).contains(rain) && (0...1).contains(cloud) && (0...60).contains(wind) &&
        (0...360).contains(direction) && (0...1).contains(thunder) && (0...1).contains(mist)
    }
    var values: [Double] { [rain,cloud,wind,direction,thunder,mist] }
    init(rain:Double,cloud:Double,wind:Double,direction:Double,thunder:Double,mist:Double) {
        self.rain=rain;self.cloud=cloud;self.wind=wind;self.direction=direction;self.thunder=thunder;self.mist=mist
    }
    init(_ values:[Double]) { self.init(rain:values[0],cloud:values[1],wind:values[2],direction:values[3],thunder:values[4],mist:values[5]) }
}

// Exact critically damped response; a new target preserves value AND velocity.
// The sea spectrum has its own slower phase-preserving GPU relaxation.
struct WeatherDynamics {
    private(set) var current: OceanWeather
    private(set) var target: OceanWeather
    private var velocity=[Double](repeating:0,count:6)
    init(_ initial:OceanWeather = .fair) { current=initial;target=initial }
    mutating func setTarget(_ value:OceanWeather) { guard value.isValid else { return };target=value }
    mutating func advance(_ dt:Double) {
        guard dt.isFinite && dt>0 else { return }
        var x=current.values;var goal=target.values
        goal[3]=x[3]+((goal[3]-x[3]+540).truncatingRemainder(dividingBy:360)-180)
        let response=[6.0,18.0,24.0,30.0,12.0,16.0]
        for i in 0..<6 {
            let omega=2/response[i],offset=x[i]-goal[i],v=velocity[i]
            let j=v+omega*offset,e=exp(-omega*dt)
            x[i]=goal[i]+(offset+j*dt)*e
            velocity[i]=(v-omega*j*dt)*e
        }
        x[3]=(x[3].truncatingRemainder(dividingBy:360)+360).truncatingRemainder(dividingBy:360)
        current=OceanWeather(x)
    }
}

struct WeatherReply: Decodable {
    struct Current:Decodable {
        let time:Double,interval:Double,precipitation:Double,rain:Double,showers:Double
        let weather_code:Int,cloud_cover:Double,wind_speed_10m:Double,wind_direction_10m:Double,wind_gusts_10m:Double
    }
    let current:Current
    static func decode(_ data:Data,status:Int,now:Date) throws -> (OceanWeather,Date) {
        guard status==200,data.count<=131072 else { throw Failure.invalid }
        let c=try JSONDecoder().decode(Self.self,from:data).current
        guard [c.time,c.interval,c.precipitation,c.rain,c.showers,c.cloud_cover,c.wind_speed_10m,c.wind_direction_10m,c.wind_gusts_10m].allSatisfy(\.isFinite),
              c.interval>=60,c.interval<=3600,c.rain>=0,c.showers>=0,c.precipitation>=0,
              (0...100).contains(c.cloud_cover),(0...200).contains(c.wind_speed_10m),
              (0...250).contains(c.wind_gusts_10m),(0...360).contains(c.wind_direction_10m),
              abs(now.timeIntervalSince1970-c.time)<7200 else { throw Failure.invalid }
        // Current precipitation is a sum over interval seconds, not mm/hour.
        let rate=(c.rain+c.showers)*3600/c.interval
        let rain=1-exp(-rate/18)
        let thunder=[95,96,97,99].contains(c.weather_code) ? max(0.45,rain) : 0
        let wind=min(45,max(c.wind_speed_10m,c.wind_gusts_10m*0.72))
        // Meteorological direction is FROM north; shader wind travels TOWARD.
        let direction=(c.wind_direction_10m+180).truncatingRemainder(dividingBy:360)
        let w=OceanWeather(rain:rain,cloud:max(c.cloud_cover/100,rain*0.95),wind:wind,direction:direction,
                           thunder:thunder,mist:max(rain*0.8,[45,48].contains(c.weather_code) ? 0.75 : 0))
        guard w.isValid else { throw Failure.invalid }
        return (w,Date(timeIntervalSince1970:c.time))
    }
    enum Failure:Error { case invalid }
}

// Sparse double-pulse lightning, with a periodic integer seed. CPU timing
// permits deterministic tests and avoids GPU hash differences between devices.
enum WeatherLightning {
    static func seed(_ event:Int) -> Double {
        var x=UInt32(event & 4095) &* 747796405 &+ 2891336453
        x=((x >> ((x >> 28) &+ 4)) ^ x) &* 277803737
        x=(x >> 22)^x
        return Double(x & 0xffffff)/16777216
    }
    static func peakTime(event:Int=0) -> Double { Double(event)*13+2+seed(event)*5+0.06 }
    static func flash(time:Double,thunder:Double)->Double {
        let event=Int(floor(time/13)),seed=seed(event)
        let t=time-Double(event)*13-(2+seed*5)
        func smooth(_ a:Double,_ b:Double,_ x:Double)->Double {
            let v=max(0,min(1,(x-a)/(b-a)));return v*v*(3-2*v)
        }
        let first=exp(-max(t,0)*7)*smooth(0,0.025,t)
        let second=exp(-max(t-0.19,0)*14)*smooth(0.19,0.205,t)*0.65
        return (first+second)*thunder*smooth(0.18,0.28,seed)
    }
}
