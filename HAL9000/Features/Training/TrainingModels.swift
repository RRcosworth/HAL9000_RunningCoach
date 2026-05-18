import Foundation

// MARK: - Training Session

struct TrainingSession: Identifiable, Codable {
    let id: String
    let name: String
    let type: String
    let date: String
    let distance: Double       // meters
    let duration: Int          // seconds
    let averageHeartrate: Double?
    let averagePace: Double?   // seconds per km
    let description: String?
    let status: String?
    let plannedDistance: Double?
    let plannedDuration: Int?
    let actualDistance: Double?
    let actualDuration: Int?
    let zone: String?

    // Computed display values
    var distanceKm: String {
        String(format: "%.2f km", distance / 1000)
    }

    var durationFormatted: String {
        let h = duration / 3600
        let m = (duration % 3600) / 60
        return h > 0 ? "\(h)h\(m)m" : "\(m)min"
    }

    var paceFormatted: String? {
        guard let pace = averagePace else { return nil }
        let m = Int(pace) / 60
        let s = Int(pace) % 60
        return String(format: "%d:%02d /km", m, s)
    }

    var heartRateFormatted: String? {
        guard let hr = averageHeartrate else { return nil }
        return String(format: "%.0f bpm", hr)
    }

    var isCompleted: Bool {
        if actualDistance != nil || actualDuration != nil { return true }
        guard let status else { return false }
        let value = status.lowercased()
        return value.contains("complete") || value.contains("done") || value.contains("finished") || value.contains("actual")
    }

    var planDistanceKm: String {
        guard let plannedDistance, plannedDistance > 0 else { return distanceKm }
        return String(format: "%.1f km", plannedDistance / 1000)
    }

    var completionLabel: String {
        isCompleted ? "已完成" : "计划"
    }

    var typeIcon: String {
        switch type.lowercased() {
        case "run", "virtualrun": return "figure.run"
        case "ride", "virtualride": return "bicycle"
        case "swim": return "figure.pool.swim"
        case "walk": return "figure.walk"
        case "yoga": return "figure.mind.and.body"
        default: return "figure.run"
        }
    }
}

// MARK: - Training Progress

struct TrainingProgress: Codable {
    let targetDistance: Double
    let completedDistance: Double
    let remainingDistance: Double
    let completedSessions: Int
    let plannedSessions: Int
    let guidance: String

    var completionRatio: Double {
        guard targetDistance > 0 else { return 0 }
        return min(max(completedDistance / targetDistance, 0), 1)
    }

    var percentText: String {
        String(format: "%.0f%%", completionRatio * 100)
    }

    var completedDistanceKm: String {
        String(format: "%.1f km", completedDistance / 1000)
    }

    var targetDistanceKm: String {
        String(format: "%.1f km", targetDistance / 1000)
    }

    var remainingDistanceKm: String {
        String(format: "%.1f km", max(remainingDistance, 0) / 1000)
    }
}

// MARK: - Weekly Summary

struct WeeklySummary: Codable {
    let weekStart: String
    let totalDistance: Double    // meters
    let totalDuration: Int       // seconds
    let totalActivities: Int
    let phase: String?
    let phaseDescription: String?

    var totalDistanceKm: String {
        String(format: "%.1f km", totalDistance / 1000)
    }

    var totalDurationFormatted: String {
        let h = totalDuration / 3600
        let m = (totalDuration % 3600) / 60
        return "\(h)h\(m)m"
    }
}

// MARK: - View State

enum ViewState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)
}
