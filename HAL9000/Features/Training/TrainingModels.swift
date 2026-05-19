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
    let startedAt: Date?

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

    var workoutSummary: TodayWorkoutSummary? {
        guard UUID(uuidString: id) != nil else { return nil }

        return TodayWorkoutSummary(
            id: id,
            title: name,
            startedAt: startedAt ?? Self.dateFormatter.date(from: date) ?? Date(),
            durationMinutes: Double(actualDuration ?? duration) / 60,
            distanceKm: (actualDistance ?? distance) / 1000
        )
    }

    var isRunningWorkout: Bool {
        let value = type.lowercased()
        return value.contains("run") || value.contains("跑")
    }

    var exportDistanceMeters: Double {
        plannedDistance ?? distance
    }

    var exportDurationSeconds: Int {
        plannedDuration ?? duration
    }

    var exportTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "HAL9000 跑步训练" : trimmed
    }

    var exportDate: Date {
        Self.dateFormatter.date(from: date) ?? Date()
    }

    var zoneNumber: Int? {
        guard let zone else { return nil }
        let digits = zone.compactMap { $0.wholeNumberValue }
        guard let first = digits.first else { return nil }
        return min(max(first, 1), 5)
    }

    var garminIntensity: String {
        switch zoneNumber ?? 2 {
        case 1, 2:
            return "Active"
        case 3:
            return "Active"
        default:
            return "Resting"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct TrainingWeekDay: Identifiable, Codable {
    let id: String
    let date: Date
    let weekday: String
    let title: String
    let sessions: [TrainingSession]
    let recoveryAdvice: String

    var primarySession: TrainingSession? {
        sessions.first
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var isRestDay: Bool {
        sessions.isEmpty
    }

    init(id: String, date: Date, weekday: String, title: String, sessions: [TrainingSession], recoveryAdvice: String) {
        self.id = id
        self.date = date
        self.weekday = weekday
        self.title = title
        self.sessions = sessions
        self.recoveryAdvice = recoveryAdvice
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case weekday
        case title
        case sessions
        case session
        case recoveryAdvice
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        weekday = try container.decode(String.self, forKey: .weekday)
        title = try container.decode(String.self, forKey: .title)

        if let decodedSessions = try container.decodeIfPresent([TrainingSession].self, forKey: .sessions) {
            sessions = decodedSessions
        } else if let legacySession = try container.decodeIfPresent(TrainingSession.self, forKey: .session) {
            sessions = [legacySession]
        } else {
            sessions = []
        }

        recoveryAdvice = try container.decode(String.self, forKey: .recoveryAdvice)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(weekday, forKey: .weekday)
        try container.encode(title, forKey: .title)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(recoveryAdvice, forKey: .recoveryAdvice)
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
