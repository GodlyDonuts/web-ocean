import Foundation
import CoreGraphics

// Pure frame-rate and resolution policy for the wallpaper. The host feeds it
// OS evidence; tests exercise every branch without a display or GPU.
struct PerformanceInputs: Equatable {
    enum Thermal: Int { case nominal, fair, serious, critical }
    var requestedFPS = 0            // 0 = adaptive
    var displayMaxFPS = 60
    var lowPowerMode = false
    var onBattery = false
    var thermal = Thermal.nominal
    var visibleFraction = 1.0       // approximate uncovered desktop share, 0...1
    var requestedPixelBudget = 1280.0*800
}

struct PerformanceDecision: Equatable {
    var framesPerSecond: Int        // 0 means pause rendering entirely
    var pixelBudget: Double
    var reason: String
}

enum PerformancePolicy {
    static let balancedBudget = 1280.0*800
    static let adaptiveFPS = 30

    static func decide(_ input: PerformanceInputs) -> PerformanceDecision {
        let ceiling = max(1, min(120, input.displayMaxFPS))
        var fps = input.requestedFPS > 0 ? min(input.requestedFPS, ceiling) : min(adaptiveFPS, ceiling)
        var budget = input.requestedPixelBudget.isFinite && input.requestedPixelBudget > 0 ? input.requestedPixelBudget : balancedBudget
        var reasons: [String] = []
        let adaptive = input.requestedFPS <= 0
        if adaptive && input.onBattery { fps = min(fps, 24); reasons.append("battery") }
        if input.lowPowerMode {
            fps = min(fps, adaptive ? 15 : 20); budget = min(budget, balancedBudget*0.75); reasons.append("low power")
        }
        switch input.thermal {
        case .nominal: break
        case .fair: if adaptive { fps = min(fps, 24) }; reasons.append("warm")
        case .serious: fps = min(fps, 15); budget = min(budget, balancedBudget*0.75); reasons.append("hot")
        case .critical: fps = min(fps, 6); budget = min(budget, balancedBudget*0.5); reasons.append("critical thermal")
        }
        let visible = input.visibleFraction.isFinite ? max(0, min(1, input.visibleFraction)) : 1
        if visible <= 0.0 { return PerformanceDecision(framesPerSecond: 0, pixelBudget: budget, reason: "covered") }
        if visible < 0.03 { fps = min(fps, 8); reasons.append("mostly covered") }
        else if visible < 0.15 { fps = min(fps, 15); reasons.append("mostly covered") }
        return PerformanceDecision(framesPerSecond: max(1, fps), pixelBudget: budget,
                                   reason: reasons.isEmpty ? "full quality" : reasons.joined(separator: ", "))
    }
}

// Approximates how much of a display rectangle is not covered by opaque
// windows. Rectangles share one coordinate space. Grid sampling bounds cost
// independent of window count overlap patterns.
enum DesktopCoverage {
    static func visibleFraction(of screen: CGRect, covers: [CGRect], columns: Int = 48, rows: Int = 30) -> Double {
        guard screen.width > 0, screen.height > 0, columns > 0, rows > 0 else { return 1 }
        let relevant = covers.filter { $0.intersects(screen) }
        guard !relevant.isEmpty else { return 1 }
        if relevant.contains(where: { $0.contains(screen) }) { return 0 }
        var open = 0
        for row in 0..<rows {
            let y = screen.minY + (Double(row)+0.5)*screen.height/Double(rows)
            for column in 0..<columns {
                let point = CGPoint(x: screen.minX + (Double(column)+0.5)*screen.width/Double(columns), y: y)
                if !relevant.contains(where: { $0.contains(point) }) { open += 1 }
            }
        }
        return Double(open)/Double(columns*rows)
    }
}
