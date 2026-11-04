import CoreGraphics
import Foundation

@main
struct PerformancePolicyTests {
    static func check(_ condition: Bool, _ message: String) {
        if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func main() {
        var input = PerformanceInputs()
        check(PerformancePolicy.decide(input).framesPerSecond == 30, "adaptive default is 30 FPS")
        check(PerformancePolicy.decide(input).pixelBudget == PerformancePolicy.balancedBudget, "balanced budget")
        input.requestedFPS = 60
        check(PerformancePolicy.decide(input).framesPerSecond == 60, "explicit 60 honored")
        input.displayMaxFPS = 48
        check(PerformancePolicy.decide(input).framesPerSecond == 48, "display ceiling")
        input = PerformanceInputs(); input.onBattery = true
        check(PerformancePolicy.decide(input).framesPerSecond == 24, "battery lowers adaptive rate")
        input.requestedFPS = 30
        check(PerformancePolicy.decide(input).framesPerSecond == 30, "battery keeps explicit rate")
        input = PerformanceInputs(); input.lowPowerMode = true; input.requestedPixelBudget = 4_000_000
        let low = PerformancePolicy.decide(input)
        check(low.framesPerSecond == 15 && low.pixelBudget <= PerformancePolicy.balancedBudget, "low power mode")
        input = PerformanceInputs(); input.thermal = .serious; input.requestedFPS = 60
        check(PerformancePolicy.decide(input).framesPerSecond == 15, "serious thermal clamps explicit rate")
        input.thermal = .critical
        check(PerformancePolicy.decide(input).framesPerSecond == 6, "critical thermal")
        input = PerformanceInputs(); input.visibleFraction = 0
        check(PerformancePolicy.decide(input).framesPerSecond == 0, "covered pauses")
        input.visibleFraction = 0.1
        check(PerformancePolicy.decide(input).framesPerSecond == 15, "sliver throttles")
        input.visibleFraction = 0.01
        check(PerformancePolicy.decide(input).framesPerSecond == 8, "tiny sliver throttles more")
        input.visibleFraction = .nan
        check(PerformancePolicy.decide(input).framesPerSecond == 30, "unknown coverage fails open")

        let screen = CGRect(x: 0, y: 0, width: 1000, height: 600)
        check(DesktopCoverage.visibleFraction(of: screen, covers: []) == 1, "empty desktop")
        check(DesktopCoverage.visibleFraction(of: screen, covers: [CGRect(x: -10, y: -10, width: 2000, height: 2000)]) == 0, "fully covered")
        let half = DesktopCoverage.visibleFraction(of: screen, covers: [CGRect(x: 0, y: 0, width: 500, height: 600)])
        check(abs(half-0.5) < 0.01, "half covered \(half)")
        let other = DesktopCoverage.visibleFraction(of: screen, covers: [CGRect(x: 2000, y: 0, width: 500, height: 600)])
        check(other == 1, "other display windows ignored")
        print("PASS: performance policy and desktop coverage")
    }
}
