import Foundation

enum CoachRole: String, Codable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: CoachRole
    let content: String
    let createdAt: Date

    init(id: UUID = UUID(), role: CoachRole, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

struct CoachHistoryMessage: Codable, Equatable {
    let role: String
    let content: String
}

struct CoachContext: Codable, Equatable {
    let generatedAt: Date
    let tsb: Double?
    let ctl: Double?
    let atl: Double?
    let phase: String?
    let weekDistanceKm: Double?
    let weekCompletionPct: Double?
    let hrvState: String?
    let averageHeartRate: Double?
    let restingHeartRate: Double?
    let hrZoneDistribution: CoachHRZoneDistribution?
    let recentActivities: [CoachRecentActivity]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case tsb
        case ctl
        case atl
        case phase
        case weekDistanceKm = "week_distance_km"
        case weekCompletionPct = "week_completion_pct"
        case hrvState = "hrv_state"
        case averageHeartRate = "average_heart_rate"
        case restingHeartRate = "resting_heart_rate"
        case hrZoneDistribution = "hr_zone_distribution"
        case recentActivities = "recent_activities"
    }

    var summaryRows: [(String, String)] {
        [
            ("Form", tsb.map { String(format: "TSB %.1f", $0) } ?? "--"),
            ("Fitness", ctl.map { String(format: "CTL %.1f", $0) } ?? "--"),
            ("Fatigue", atl.map { String(format: "ATL %.1f", $0) } ?? "--"),
            ("Week", weekCompletionPct.map { String(format: "%.0f%%", $0) } ?? "--"),
            ("Phase", phase ?? "未识别")
        ]
    }
}

struct CoachHRZoneDistribution: Codable, Equatable {
    let z1z2: Double
    let z3z4: Double
    let z5: Double

    enum CodingKeys: String, CodingKey {
        case z1z2 = "z1_z2"
        case z3z4 = "z3_z4"
        case z5
    }
}

struct CoachRecentActivity: Codable, Equatable {
    let date: String
    let type: String
    let distanceKm: Double
    let avgHR: Double?

    enum CodingKeys: String, CodingKey {
        case date
        case type
        case distanceKm = "distance_km"
        case avgHR = "avg_hr"
    }
}

struct CoachChatRequest: Codable, Equatable {
    let context: CoachContext
    let message: String
    let history: [CoachHistoryMessage]
}

struct CoachChatResponse: Codable, Equatable {
    let reply: String
    let planPatch: CoachPlanPatch?
    let tokensUsed: Int?

    enum CodingKeys: String, CodingKey {
        case reply
        case planPatch = "plan_patch"
        case tokensUsed = "tokens_used"
    }
}

struct CoachPlanPatch: Codable, Equatable {
    let weekStart: String?
    let sessions: [CoachPlanSession]

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case sessions
    }
}

struct CoachPlanSession: Codable, Equatable {
    let day: String?
    let type: String
    let distanceKm: Double?
    let zone: String?
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case day
        case type
        case distanceKm = "distance_km"
        case zone
        case detail
    }
}

enum CoachState: Equatable {
    case idle
    case loading
    case failed(String)
}
