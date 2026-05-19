import Foundation

struct CoachContextCollector {
    private let healthService: HealthKitServing
    private let loadCalculator: TrainingLoadCalculator
    private let calendar: Calendar

    init(
        healthService: HealthKitServing = HealthKitService.shared,
        loadCalculator: TrainingLoadCalculator = TrainingLoadCalculator(),
        calendar: Calendar = .current
    ) {
        self.healthService = healthService
        self.loadCalculator = loadCalculator
        self.calendar = calendar
    }

    func collect() async -> CoachContext {
        async let loadDaysResult = result { try await healthService.fetchRunningLoadDays(days: 180) }
        async let weeklyDistanceResult = result { try await healthService.fetchWeeklyRunningDistance() }
        async let keyMetricsResult = result { try await healthService.fetchRunningKeyMetrics() }
        async let hrvResult = result { try await healthService.fetchHRVMetric() }
        async let samplesResult = result { try await healthService.fetchHeartRateSamples(days: 7) }
        async let maxHRResult = result { try await healthService.fetchMaxHeartRate() }

        let loadDays = await loadDaysResult.value ?? []
        let tsbResult = loadCalculator.calculateTSB(days: loadDays)
        let weeklyDistance = await weeklyDistanceResult.value
        let keyMetrics = await keyMetricsResult.value
        let hrv = await hrvResult.value
        let samples = await samplesResult.value ?? []
        let maxHR = await maxHRResult.value ?? 190

        let recentActivities = loadDays
            .filter { $0.runningDistanceKm > 0 || $0.exerciseMinutes > 0 }
            .sorted { $0.date > $1.date }
            .prefix(5)
            .map { day in
                CoachRecentActivity(
                    date: Self.dateString(day.date),
                    type: "Run",
                    distanceKm: day.runningDistanceKm,
                    avgHR: day.averageHeartRate
                )
            }

        let activeDays = loadDays.filter { $0.runningDistanceKm > 0 || $0.exerciseMinutes > 0 }
        let hasEnoughTSBData = activeDays.count >= 42
        let currentTSB = hasEnoughTSBData ? tsbResult.current.tsb : nil

        return CoachContext(
            generatedAt: Date(),
            tsb: currentTSB,
            ctl: hasEnoughTSBData ? tsbResult.current.ctl : nil,
            atl: hasEnoughTSBData ? tsbResult.current.atl : nil,
            phase: phase(for: activeDays),
            weekDistanceKm: weeklyDistance?.distanceKm,
            weekCompletionPct: nil,
            hrvState: hrv?.state.title,
            averageHeartRate: keyMetrics?.averageHeartRate,
            restingHeartRate: keyMetrics?.restingHeartRate,
            hrZoneDistribution: zoneDistribution(samples: samples, maxHR: maxHR),
            recentActivities: Array(recentActivities)
        )
    }

    private func result<T>(_ operation: () async throws -> T) async -> (value: T?, error: Error?) {
        do {
            return (try await operation(), nil)
        } catch {
            return (nil, error)
        }
    }

    private func phase(for days: [RunningLoadDay]) -> String? {
        guard !days.isEmpty else { return nil }
        let recent = days.sorted { $0.date > $1.date }.prefix(28)
        let weeklyKm = recent.reduce(0) { $0 + $1.runningDistanceKm } / 4

        switch weeklyKm {
        case 0..<25:
            return "恢复/基础期"
        case 25..<55:
            return "基础期"
        case 55..<80:
            return "建设期"
        default:
            return "专项/峰值期"
        }
    }

    private func zoneDistribution(samples: [HeartRateSample], maxHR: Double) -> CoachHRZoneDistribution? {
        guard !samples.isEmpty, maxHR > 0 else { return nil }
        let calculator = HeartRateZoneCalculator()
        var z1z2 = 0
        var z3z4 = 0
        var z5 = 0

        for sample in samples {
            switch calculator.classify(heartRate: sample.value, maxHR: maxHR) {
            case 1, 2:
                z1z2 += 1
            case 3, 4:
                z3z4 += 1
            default:
                z5 += 1
            }
        }

        let total = Double(samples.count)
        return CoachHRZoneDistribution(
            z1z2: Double(z1z2) / total * 100,
            z3z4: Double(z3z4) / total * 100,
            z5: Double(z5) / total * 100
        )
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
