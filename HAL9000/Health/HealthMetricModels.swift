import Foundation

struct TodayHealthSnapshot: Equatable {
    let generatedAt: Date
    let shortTermLoad: TrainingLoadMetric
    let longTermLoad: TrainingLoadMetric
    let loadBalance: LoadBalanceState
    let hrv: HRVMetric
    let bodyMass: BodyMassMetric
    let todayActivity: TodayActivityMetric
    let weeklyRunning: RunningDistanceMetric
    let monthlyRunning: RunningDistanceMetric
    let runningKeyMetrics: RunningKeyMetrics
    let loadHistory: [TrainingLoadHistoryPoint]
    let hrvHistory: [HealthValuePoint]
    let bodyMassHistory: [HealthValuePoint]
    let weeklyRunningHistory: [HealthValuePoint]
    let monthlyRunningHistory: [HealthValuePoint]
    let tsbData: TSBDisplayData?
    let loadFocus: TrainingLoadFocusData?
    let heartRateDistribution: HeartRateZoneDistribution?
}

struct TrainingLoadMetric: Equatable {
    let value: Double?
    let label: String
    let trend: MetricTrend
    let subtitle: String

    var displayValue: String {
        guard let value else { return "--" }
        return String(format: "%.0f", value)
    }
}

enum MetricTrend: Equatable {
    case up
    case stable
    case down
    case unknown
}

enum LoadBalanceState: Equatable {
    case fresh
    case productive
    case strained
    case detraining
    case unknown

    var title: String {
        switch self {
        case .fresh: return "身体轻松"
        case .productive: return "状态稳定"
        case .strained: return "负荷偏高"
        case .detraining: return "负荷下降"
        case .unknown: return "数据不足"
        }
    }

    var guidance: String {
        switch self {
        case .fresh: return "适合安排质量训练"
        case .productive: return "可以正常训练"
        case .strained: return "建议轻松跑或休息"
        case .detraining: return "建议逐步恢复跑量"
        case .unknown: return "完成更多训练后生成建议"
        }
    }
}

struct HRVMetric: Equatable {
    let latestMs: Double?
    let sevenDayAverageMs: Double?
    let baselineMs: Double?
    let state: HRVState
}

enum HRVState: Equatable {
    case aboveBaseline
    case normal
    case belowBaseline
    case noData

    var title: String {
        switch self {
        case .aboveBaseline: return "高于基线"
        case .normal: return "正常"
        case .belowBaseline: return "低于基线"
        case .noData: return "暂无数据"
        }
    }

    var guidance: String {
        switch self {
        case .aboveBaseline: return "恢复状态不错"
        case .normal: return "保持当前节奏"
        case .belowBaseline: return "建议降低训练强度"
        case .noData: return "佩戴 Apple Watch 后可记录"
        }
    }
}

struct BodyMassMetric: Equatable {
    let latestKg: Double?
    let updatedAt: Date?
    let trend30dKg: Double?
}

struct TodayActivityMetric: Equatable {
    let exerciseMinutes: Double
    let activeEnergyKcal: Double
    let steps: Double
    let runningDistanceKm: Double
    let workouts: [TodayWorkoutSummary]
}

struct TodayWorkoutSummary: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let startedAt: Date
    let durationMinutes: Double
    let distanceKm: Double?
}

struct WorkoutDetail: Equatable {
    let id: String
    let title: String
    let startedAt: Date
    let endedAt: Date
    let duration: TimeInterval
    let distanceKm: Double?
    let activeEnergyKcal: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let route: [WorkoutRoutePoint]
    let heartRateSamples: [HeartRateSample]
    let splits: [WorkoutSplit]

    var durationMinutes: Double {
        duration / 60
    }

    var paceText: String {
        guard let distanceKm, distanceKm > 0 else { return "--" }
        let secondsPerKm = duration / distanceKm
        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }
}

struct WorkoutRoutePoint: Identifiable, Equatable {
    let id = UUID()
    let latitude: Double
    let longitude: Double
    let date: Date

    static func == (lhs: WorkoutRoutePoint, rhs: WorkoutRoutePoint) -> Bool {
        lhs.latitude == rhs.latitude &&
        lhs.longitude == rhs.longitude &&
        lhs.date == rhs.date
    }
}

struct WorkoutSplit: Identifiable, Equatable {
    let id = UUID()
    let kilometer: Int
    let duration: TimeInterval
    let averageHeartRate: Double?

    static func == (lhs: WorkoutSplit, rhs: WorkoutSplit) -> Bool {
        lhs.kilometer == rhs.kilometer &&
        lhs.duration == rhs.duration &&
        lhs.averageHeartRate == rhs.averageHeartRate
    }
}

struct RunningDistanceMetric: Equatable {
    let distanceKm: Double?
    let subtitle: String
    let isEstimated: Bool

    var displayValue: String {
        guard let distanceKm else { return "--" }
        return String(format: "%.1f km", distanceKm)
    }
}

struct RunningKeyMetrics: Equatable {
    let latestPace: String?
    let averageHeartRate: Double?
    let restingHeartRate: Double?
    let runningPower: Double?
    let runningSpeed: Double?
    let strideLengthCm: Double?
    let groundContactTimeMs: Double?
    let verticalOscillationCm: Double?
}

struct RunningLoadDay: Equatable {
    let date: Date
    let runningDistanceKm: Double
    let exerciseMinutes: Double
    let averageHeartRate: Double?
    let restingHeartRate: Double?
}

struct HealthValuePoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let value: Double

    static func == (lhs: HealthValuePoint, rhs: HealthValuePoint) -> Bool {
        lhs.date == rhs.date && lhs.value == rhs.value
    }
}

struct TrainingLoadHistoryPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let shortTermLoad: Double?
    let longTermLoad: Double?
    let balance: LoadBalanceState

    static func == (lhs: TrainingLoadHistoryPoint, rhs: TrainingLoadHistoryPoint) -> Bool {
        lhs.date == rhs.date &&
        lhs.shortTermLoad == rhs.shortTermLoad &&
        lhs.longTermLoad == rhs.longTermLoad &&
        lhs.balance == rhs.balance
    }
}

struct TSBDisplayData: Equatable {
    let ctl: Double
    let atl: Double
    let tsb: Double
    let state: TSBState
    let stateTitle: String
    let history: [TSBChartPoint]

    struct TSBChartPoint: Identifiable, Equatable {
        let id = UUID()
        let date: Date
        let ctl: Double
        let atl: Double
        let tsb: Double

        static func == (lhs: TSBChartPoint, rhs: TSBChartPoint) -> Bool {
            lhs.date == rhs.date &&
            lhs.ctl == rhs.ctl &&
            lhs.atl == rhs.atl &&
            lhs.tsb == rhs.tsb
        }
    }
}

struct HeartRateSample: Equatable {
    let date: Date
    let value: Double
}

struct HeartRateZoneDistribution: Equatable {
    let period: String
    let zones: [HRZoneBreakdown]
    let totalMinutes: Double
}

struct HRZoneBreakdown: Identifiable, Equatable {
    let id = UUID()
    let zone: Int
    let name: String
    let rangeText: String
    let minutes: Double
    let percentage: Double

    static func == (lhs: HRZoneBreakdown, rhs: HRZoneBreakdown) -> Bool {
        lhs.zone == rhs.zone &&
        lhs.name == rhs.name &&
        lhs.rangeText == rhs.rangeText &&
        lhs.minutes == rhs.minutes &&
        lhs.percentage == rhs.percentage
    }
}

struct DailyLoadFocus: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let anaerobic: Double
    let highAerobic: Double
    let lowAerobic: Double

    static func == (lhs: DailyLoadFocus, rhs: DailyLoadFocus) -> Bool {
        lhs.date == rhs.date &&
        lhs.anaerobic == rhs.anaerobic &&
        lhs.highAerobic == rhs.highAerobic &&
        lhs.lowAerobic == rhs.lowAerobic
    }
}

struct TrainingLoadFocusData: Equatable {
    let period: String
    let anaerobic: Double
    let anaerobicPercent: Double
    let highAerobic: Double
    let highAerobicPercent: Double
    let lowAerobic: Double
    let lowAerobicPercent: Double
    let dailyBreakdown: [DailyLoadFocus]
}
