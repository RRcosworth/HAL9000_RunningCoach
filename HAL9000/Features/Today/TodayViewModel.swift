import Foundation

enum TodayState: Equatable {
    case idle
    case requestingPermission
    case permissionRequired
    case loading
    case loaded
    case partialData(String)
    case failed(String)
}

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var state: TodayState = .idle
    @Published var snapshot: TodayHealthSnapshot?

    private let healthService: HealthKitServing
    private let loadCalculator: TrainingLoadCalculator
    private var supplementalTask: Task<Void, Never>?

    init(
        healthService: HealthKitServing = HealthKitService.shared,
        loadCalculator: TrainingLoadCalculator = TrainingLoadCalculator()
    ) {
        self.healthService = healthService
        self.loadCalculator = loadCalculator
    }

    func load() async {
        switch await healthService.authorizationState() {
        case .unavailable:
            state = .failed("此设备不支持 Apple 健康")
        case .notDetermined, .sharingDenied:
            state = .permissionRequired
        case .authorized:
            await loadHealthSnapshot()
        }
    }

    func requestHealthAuthorization() async {
        state = .requestingPermission

        do {
            try await healthService.requestAuthorization()
            await loadHealthSnapshot()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        await loadHealthSnapshot()
    }

    private func loadHealthSnapshot() async {
        if snapshot == nil {
            state = .loading
        }

        async let todayResult = result { [self] in try await self.healthService.fetchTodayActivity() }
        async let weeklyResult = result { [self] in try await self.healthService.fetchWeeklyRunningDistance() }
        async let monthlyResult = result { [self] in try await self.healthService.fetchMonthlyRunningDistance() }
        async let hrvResult = result { [self] in try await self.healthService.fetchHRVMetric() }
        async let bodyMassResult = result { [self] in try await self.healthService.fetchBodyMassMetric() }
        async let keyMetricsResult = result { [self] in try await self.healthService.fetchRunningKeyMetrics() }
        async let loadDaysResult = result { [self] in try await self.healthService.fetchRunningLoadDays(days: 42) }
        async let loadHistoryDaysResult = result { [self] in try await self.healthService.fetchRunningLoadDays(days: 132) }
        async let hrvHistoryResult = result { [self] in try await self.healthService.fetchHRVHistory(days: 90) }
        async let bodyMassHistoryResult = result { [self] in try await self.healthService.fetchBodyMassHistory(days: 90) }
        async let weeklyRunningHistoryResult = result { [self] in try await self.healthService.fetchWeeklyRunningHistory(weeks: 12) }
        async let monthlyRunningHistoryResult = result { [self] in try await self.healthService.fetchMonthlyRunningHistory(months: 12) }

        let today = await todayResult.value ?? TodayActivityMetric(
            exerciseMinutes: 0,
            activeEnergyKcal: 0,
            steps: 0,
            runningDistanceKm: 0,
            workouts: []
        )
        let weekly = await weeklyResult.value ?? RunningDistanceMetric(distanceKm: nil, subtitle: "本周已完成", isEstimated: false)
        let monthly = await monthlyResult.value ?? RunningDistanceMetric(distanceKm: nil, subtitle: "本月累计", isEstimated: false)
        let hrv = await hrvResult.value ?? HRVMetric(latestMs: nil, sevenDayAverageMs: nil, baselineMs: nil, state: .noData)
        let bodyMass = await bodyMassResult.value ?? BodyMassMetric(latestKg: nil, updatedAt: nil, trend30dKg: nil)
        let keyMetrics = await keyMetricsResult.value ?? RunningKeyMetrics(
            latestPace: nil,
            averageHeartRate: nil,
            restingHeartRate: nil,
            runningPower: nil,
            runningSpeed: nil,
            strideLengthCm: nil,
            groundContactTimeMs: nil,
            verticalOscillationCm: nil
        )
        let loadDays = await loadDaysResult.value ?? []
        let load = loadCalculator.calculate(days: loadDays)
        let loadHistoryDays = await loadHistoryDaysResult.value ?? loadDays
        let loadHistory = loadCalculator.calculateHistory(days: loadHistoryDays, displayDays: 90)

        let generatedAt = Date()

        snapshot = TodayHealthSnapshot(
            generatedAt: generatedAt,
            shortTermLoad: load.shortTerm,
            longTermLoad: load.longTerm,
            loadBalance: load.balance,
            hrv: hrv,
            bodyMass: bodyMass,
            todayActivity: today,
            weeklyRunning: weekly,
            monthlyRunning: monthly,
            runningKeyMetrics: keyMetrics,
            loadHistory: loadHistory,
            hrvHistory: await hrvHistoryResult.value ?? [],
            bodyMassHistory: await bodyMassHistoryResult.value ?? [],
            weeklyRunningHistory: await weeklyRunningHistoryResult.value ?? [],
            monthlyRunningHistory: await monthlyRunningHistoryResult.value ?? [],
            tsbData: snapshot?.tsbData,
            loadFocus: snapshot?.loadFocus,
            heartRateDistribution: snapshot?.heartRateDistribution
        )

        let failures = await [
            todayResult.error,
            weeklyResult.error,
            monthlyResult.error,
            hrvResult.error,
            bodyMassResult.error,
            keyMetricsResult.error,
            loadDaysResult.error,
            loadHistoryDaysResult.error,
            hrvHistoryResult.error,
            bodyMassHistoryResult.error,
            weeklyRunningHistoryResult.error,
            monthlyRunningHistoryResult.error
        ].compactMap { $0 }

        state = failures.isEmpty ? .loaded : .partialData("部分 Apple 健康指标暂不可用")
        supplementalTask?.cancel()
        supplementalTask = Task { [weak self] in
            await self?.loadSupplementalHealthData(for: generatedAt)
        }
    }

    private func loadSupplementalHealthData(for generatedAt: Date) async {
        async let tsbResult = result { [self] in try await self.loadTSBData() }
        async let heartRateSamplesResult = result { [self] in try await self.healthService.fetchHeartRateSamples(days: 28) }
        async let maxHeartRateResult = result { [self] in try await self.healthService.fetchMaxHeartRate() }

        guard !Task.isCancelled,
              let currentSnapshot = snapshot,
              currentSnapshot.generatedAt == generatedAt
        else { return }

        let samples = await heartRateSamplesResult.value ?? []
        let maxHR = await maxHeartRateResult.value ?? 190
        let focus = buildLoadFocus(samples: samples, maxHR: maxHR, days: 28)
        let distribution = buildHRDistribution(samples: samples, maxHR: maxHR, days: 7)

        guard !Task.isCancelled,
              let latestSnapshot = snapshot,
              latestSnapshot.generatedAt == generatedAt
        else { return }

        snapshot = TodayHealthSnapshot(
            generatedAt: latestSnapshot.generatedAt,
            shortTermLoad: latestSnapshot.shortTermLoad,
            longTermLoad: latestSnapshot.longTermLoad,
            loadBalance: latestSnapshot.loadBalance,
            hrv: latestSnapshot.hrv,
            bodyMass: latestSnapshot.bodyMass,
            todayActivity: latestSnapshot.todayActivity,
            weeklyRunning: latestSnapshot.weeklyRunning,
            monthlyRunning: latestSnapshot.monthlyRunning,
            runningKeyMetrics: latestSnapshot.runningKeyMetrics,
            loadHistory: latestSnapshot.loadHistory,
            hrvHistory: latestSnapshot.hrvHistory,
            bodyMassHistory: latestSnapshot.bodyMassHistory,
            weeklyRunningHistory: latestSnapshot.weeklyRunningHistory,
            monthlyRunningHistory: latestSnapshot.monthlyRunningHistory,
            tsbData: await tsbResult.value,
            loadFocus: focus,
            heartRateDistribution: distribution
        )
    }

    private func loadTSBData() async throws -> TSBDisplayData {
        let days = try await healthService.fetchRunningLoadDays(days: 180)
        let tsbResult = loadCalculator.calculateTSB(days: days)
        let hasEnoughData = days.filter { $0.runningDistanceKm > 0 || $0.exerciseMinutes > 0 }.count >= 42
        let state = TSBCalculator().state(for: tsbResult.current.tsb, hasEnoughData: hasEnoughData)

        return TSBDisplayData(
            ctl: tsbResult.current.ctl,
            atl: tsbResult.current.atl,
            tsb: tsbResult.current.tsb,
            state: state,
            stateTitle: state.title,
            history: tsbResult.history.map {
                TSBDisplayData.TSBChartPoint(date: $0.date, ctl: $0.ctl, atl: $0.atl, tsb: $0.tsb)
            }
        )
    }

    private func loadLoadFocus() async throws -> TrainingLoadFocusData {
        let samples = try await healthService.fetchHeartRateSamples(days: 28)
        let maxHR = try await healthService.fetchMaxHeartRate()
        return buildLoadFocus(samples: samples, maxHR: maxHR, days: 28)
    }

    private func buildLoadFocus(samples: [HeartRateSample], maxHR: Double, days: Int) -> TrainingLoadFocusData {
        let calculator = HeartRateZoneCalculator()
        let calendar = Calendar.current
        let period = periodText(days: days)

        var low = 0.0
        var high = 0.0
        var anaerobic = 0.0
        var daily: [Date: (low: Double, high: Double, anaerobic: Double)] = [:]

        for sample in samples {
            let load = loadMinutes(for: sample.value, maxHR: maxHR)
            let day = calendar.startOfDay(for: sample.date)
            var bucket = daily[day] ?? (0, 0, 0)

            switch calculator.loadType(heartRate: sample.value, maxHR: maxHR) {
            case .lowAerobic:
                low += load
                bucket.low += load
            case .highAerobic:
                high += load
                bucket.high += load
            case .anaerobic:
                anaerobic += load
                bucket.anaerobic += load
            }

            daily[day] = bucket
        }

        let total = low + high + anaerobic
        return TrainingLoadFocusData(
            period: period,
            anaerobic: anaerobic,
            anaerobicPercent: percent(anaerobic, total: total),
            highAerobic: high,
            highAerobicPercent: percent(high, total: total),
            lowAerobic: low,
            lowAerobicPercent: percent(low, total: total),
            dailyBreakdown: daily.map { date, values in
                DailyLoadFocus(date: date, anaerobic: values.anaerobic, highAerobic: values.high, lowAerobic: values.low)
            }
            .sorted { $0.date < $1.date }
        )
    }

    private func loadHRDistribution() async throws -> HeartRateZoneDistribution {
        let samples = try await healthService.fetchHeartRateSamples(days: 7)
        let maxHR = try await healthService.fetchMaxHeartRate()
        return buildHRDistribution(samples: samples, maxHR: maxHR, days: 7)
    }

    private func buildHRDistribution(samples: [HeartRateSample], maxHR: Double, days: Int) -> HeartRateZoneDistribution {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days + 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let calculator = HeartRateZoneCalculator()
        var minutesByZone = Dictionary(uniqueKeysWithValues: (1...5).map { ($0, 0.0) })

        for sample in samples where sample.date >= cutoff {
            let zone = calculator.classify(heartRate: sample.value, maxHR: maxHR)
            minutesByZone[zone, default: 0] += loadMinutes(for: sample.value, maxHR: maxHR)
        }

        let total = minutesByZone.values.reduce(0, +)
        let zones = (1...5).map { zone in
            let minutes = minutesByZone[zone] ?? 0
            return HRZoneBreakdown(
                zone: zone,
                name: calculator.zoneName(zone),
                rangeText: calculator.zoneRange(zone: zone, maxHR: maxHR),
                minutes: minutes,
                percentage: percent(minutes, total: total)
            )
        }

        return HeartRateZoneDistribution(period: periodText(days: days), zones: zones, totalMinutes: total)
    }

    private func loadMinutes(for heartRate: Double, maxHR: Double) -> Double {
        guard maxHR > 0 else { return 0 }
        let intensity = min(max(heartRate / maxHR, 0.5), 1.2)
        return intensity
    }

    private func percent(_ value: Double, total: Double) -> Double {
        guard total > 0 else { return 0 }
        return value / total * 100
    }

    private func periodText(days: Int) -> String {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days + 1, to: end) ?? end
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func result<T>(_ operation: @escaping () async throws -> T) async -> (value: T?, error: String?) {
        do {
            return (try await operation(), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }
}
