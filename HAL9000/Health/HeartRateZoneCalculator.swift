import Foundation

struct HeartRateZoneCalculator {
    enum LoadType {
        case lowAerobic
        case highAerobic
        case anaerobic
    }

    func classify(heartRate: Double, maxHR: Double) -> Int {
        guard maxHR > 0 else { return 1 }
        let percentage = heartRate / maxHR
        switch percentage {
        case ..<0.60: return 1
        case ..<0.70: return 2
        case ..<0.80: return 3
        case ..<0.90: return 4
        default: return 5
        }
    }

    func zoneName(_ zone: Int) -> String {
        switch zone {
        case 1: return "Very Easy"
        case 2: return "Easy"
        case 3: return "Moderate"
        case 4: return "Hard"
        case 5: return "Very Hard"
        default: return "Unknown"
        }
    }

    func zoneRange(zone: Int, maxHR: Double) -> String {
        let bounds: [(Double, Double)] = [
            (0.50, 0.60),
            (0.60, 0.70),
            (0.70, 0.80),
            (0.80, 0.90),
            (0.90, 1.00)
        ]
        guard bounds.indices.contains(zone - 1) else { return "--" }
        let bound = bounds[zone - 1]
        return String(format: "%.0f-%.0f bpm", bound.0 * maxHR, bound.1 * maxHR)
    }

    func loadType(heartRate: Double, maxHR: Double) -> LoadType {
        guard maxHR > 0 else { return .lowAerobic }
        let percentage = heartRate / maxHR
        if percentage < 0.70 { return .lowAerobic }
        if percentage < 0.90 { return .highAerobic }
        return .anaerobic
    }
}
