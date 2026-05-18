import Foundation
import HealthKit

protocol HealthKitServing {
    func requestAuthorization() async throws
    func authorizationState() async -> HealthAuthorizationState
    func fetchTodayActivity() async throws -> TodayActivityMetric
    func fetchWeeklyRunningDistance() async throws -> RunningDistanceMetric
    func fetchMonthlyRunningDistance() async throws -> RunningDistanceMetric
    func fetchHRVMetric() async throws -> HRVMetric
    func fetchBodyMassMetric() async throws -> BodyMassMetric
    func fetchRunningKeyMetrics() async throws -> RunningKeyMetrics
    func fetchRunningLoadDays(days: Int) async throws -> [RunningLoadDay]
    func fetchHRVHistory(days: Int) async throws -> [HealthValuePoint]
    func fetchBodyMassHistory(days: Int) async throws -> [HealthValuePoint]
    func fetchWeeklyRunningHistory(weeks: Int) async throws -> [HealthValuePoint]
    func fetchMonthlyRunningHistory(months: Int) async throws -> [HealthValuePoint]
    func fetchHeartRateSamples(days: Int) async throws -> [HeartRateSample]
    func fetchMaxHeartRate() async throws -> Double
}

enum HealthKitServiceError: LocalizedError {
    case unavailable
    case missingType(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "此设备不支持 Apple 健康"
        case .missingType(let name):
            return "Apple 健康缺少 \(name) 数据类型"
        }
    }
}

actor HealthKitService: HealthKitServing {
    static let shared = HealthKitService()

    private let healthStore = HKHealthStore()
    private let calendar = Calendar.current
    private let authorizationRequestVersion = 1
    private let authorizationRequestVersionKey = "healthKitAuthorizationRequestVersion"

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitServiceError.unavailable
        }

        guard !hasRequestedAuthorization else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: Set<HKSampleType>(), read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if success {
                    UserDefaults.standard.set(self.authorizationRequestVersion, forKey: self.authorizationRequestVersionKey)
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: HealthKitServiceError.unavailable)
                }
            }
        }
    }

    func authorizationState() async -> HealthAuthorizationState {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        if hasRequestedAuthorization { return .authorized }
        guard let stepType = quantityType(.stepCount) else { return .unavailable }

        switch healthStore.authorizationStatus(for: stepType) {
        case .notDetermined:
            return .notDetermined
        case .sharingDenied:
            return .sharingDenied
        case .sharingAuthorized:
            return .authorized
        @unknown default:
            return .notDetermined
        }
    }

    private var hasRequestedAuthorization: Bool {
        UserDefaults.standard.integer(forKey: authorizationRequestVersionKey) >= authorizationRequestVersion
    }

    func fetchTodayActivity() async throws -> TodayActivityMetric {
        let now = Date()
        let start = calendar.startOfDay(for: now)

        async let exercise = sumQuantity(.appleExerciseTime, unit: .minute(), from: start, to: now)
        async let energy = sumQuantity(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: now)
        async let steps = sumQuantity(.stepCount, unit: .count(), from: start, to: now)
        async let runningDistance = runningDistance(from: start, to: now)
        async let workouts = runningWorkouts(from: start, to: now)

        let todayWorkouts = try await workouts.map { workout in
            TodayWorkoutSummary(
                id: workout.uuid.uuidString,
                title: workout.workoutActivityType == .running ? "跑步" : "运动",
                startedAt: workout.startDate,
                durationMinutes: workout.duration / 60,
                distanceKm: workoutDistanceKm(workout)
            )
        }

        return TodayActivityMetric(
            exerciseMinutes: try await exercise,
            activeEnergyKcal: try await energy,
            steps: try await steps,
            runningDistanceKm: try await runningDistance,
            workouts: todayWorkouts
        )
    }

    func fetchWeeklyRunningDistance() async throws -> RunningDistanceMetric {
        let now = Date()
        let start = startOfWeek(for: now)
        let distance = try await runningDistance(from: start, to: now)

        return RunningDistanceMetric(
            distanceKm: distance,
            subtitle: "本周已完成",
            isEstimated: false
        )
    }

    func fetchMonthlyRunningDistance() async throws -> RunningDistanceMetric {
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        let start = calendar.date(from: components) ?? calendar.startOfDay(for: now)
        let distance = try await runningDistance(from: start, to: now)

        return RunningDistanceMetric(
            distanceKm: distance,
            subtitle: "\(calendar.component(.month, from: now))月累计",
            isEstimated: false
        )
    }

    func fetchHRVMetric() async throws -> HRVMetric {
        let now = Date()
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let twentyEightDaysAgo = calendar.date(byAdding: .day, value: -28, to: now) ?? now

        async let latest = latestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: twentyEightDaysAgo, to: now)
        async let sevenDayAverage = averageQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: sevenDaysAgo, to: now)
        async let baseline = averageQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: twentyEightDaysAgo, to: now)

        let latestSample = try await latest
        let sevenDayValue = try await sevenDayAverage
        let baselineValue = try await baseline

        return HRVMetric(
            latestMs: latestSample?.value,
            sevenDayAverageMs: sevenDayValue,
            baselineMs: baselineValue,
            state: hrvState(sevenDayAverage: sevenDayValue, baseline: baselineValue)
        )
    }

    func fetchBodyMassMetric() async throws -> BodyMassMetric {
        let now = Date()
        let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: now) ?? now
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now

        async let latest = latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo), from: ninetyDaysAgo, to: now)
        async let thirtyDay = nearestQuantity(.bodyMass, unit: .gramUnit(with: .kilo), near: thirtyDaysAgo, toleranceDays: 7)

        let latestSample = try await latest
        let trendSample = try await thirtyDay

        let trend: Double?
        if let latestValue = latestSample?.value, let previousValue = trendSample?.value {
            trend = latestValue - previousValue
        } else {
            trend = nil
        }

        return BodyMassMetric(
            latestKg: latestSample?.value,
            updatedAt: latestSample?.date,
            trend30dKg: trend
        )
    }

    func fetchRunningKeyMetrics() async throws -> RunningKeyMetrics {
        let now = Date()
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now

        async let restingHeartRate = latestQuantity(.restingHeartRate, unit: .count().unitDivided(by: .minute()), from: thirtyDaysAgo, to: now)
        async let averageHeartRate = averageQuantity(.heartRate, unit: .count().unitDivided(by: .minute()), from: thirtyDaysAgo, to: now)
        async let runningPower = latestQuantity(.runningPower, unit: .watt(), from: thirtyDaysAgo, to: now)
        async let runningSpeed = latestQuantity(.runningSpeed, unit: .meter().unitDivided(by: .second()), from: thirtyDaysAgo, to: now)
        async let strideLength = latestQuantity(.runningStrideLength, unit: .meterUnit(with: .centi), from: thirtyDaysAgo, to: now)
        async let contactTime = latestQuantity(.runningGroundContactTime, unit: .secondUnit(with: .milli), from: thirtyDaysAgo, to: now)
        async let verticalOscillation = latestQuantity(.runningVerticalOscillation, unit: .meterUnit(with: .centi), from: thirtyDaysAgo, to: now)

        let speedSample = try await runningSpeed
        let restingHeartRateSample = try await restingHeartRate
        let runningPowerSample = try await runningPower
        let strideLengthSample = try await strideLength
        let contactTimeSample = try await contactTime
        let verticalOscillationSample = try await verticalOscillation

        return RunningKeyMetrics(
            latestPace: paceString(fromMetersPerSecond: speedSample?.value),
            averageHeartRate: try await averageHeartRate,
            restingHeartRate: restingHeartRateSample?.value,
            runningPower: runningPowerSample?.value,
            runningSpeed: speedSample?.value,
            strideLengthCm: strideLengthSample?.value,
            groundContactTimeMs: contactTimeSample?.value,
            verticalOscillationCm: verticalOscillationSample?.value
        )
    }

    func fetchRunningLoadDays(days: Int) async throws -> [RunningLoadDay] {
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -days + 1, to: calendar.startOfDay(for: now)) ?? now
        let workouts = try await runningWorkouts(from: start, to: now)
        let restingHeartRate = try await latestQuantity(.restingHeartRate, unit: .count().unitDivided(by: .minute()), from: start, to: now)?.value

        var buckets: [Date: RunningLoadDay] = [:]

        for offset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            buckets[dayStart] = RunningLoadDay(
                date: dayStart,
                runningDistanceKm: 0,
                exerciseMinutes: 0,
                averageHeartRate: nil,
                restingHeartRate: restingHeartRate
            )
        }

        for workout in workouts {
            let dayStart = calendar.startOfDay(for: workout.startDate)
            let current = buckets[dayStart] ?? RunningLoadDay(
                date: dayStart,
                runningDistanceKm: 0,
                exerciseMinutes: 0,
                averageHeartRate: nil,
                restingHeartRate: restingHeartRate
            )

            buckets[dayStart] = RunningLoadDay(
                date: dayStart,
                runningDistanceKm: current.runningDistanceKm + (workoutDistanceKm(workout) ?? 0),
                exerciseMinutes: current.exerciseMinutes + workout.duration / 60,
                averageHeartRate: current.averageHeartRate,
                restingHeartRate: restingHeartRate
            )
        }

        return buckets.values.sorted { $0.date > $1.date }
    }

    func fetchHRVHistory(days: Int) async throws -> [HealthValuePoint] {
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -days + 1, to: calendar.startOfDay(for: now)) ?? now
        let samples = try await quantitySamples(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: start, to: now)
        let grouped = Dictionary(grouping: samples) { calendar.startOfDay(for: $0.date) }

        return grouped.map { date, samples in
            HealthValuePoint(date: date, value: samples.map(\.value).reduce(0, +) / Double(samples.count))
        }
        .sorted { $0.date < $1.date }
    }

    func fetchBodyMassHistory(days: Int) async throws -> [HealthValuePoint] {
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -days + 1, to: calendar.startOfDay(for: now)) ?? now
        return try await quantitySamples(.bodyMass, unit: .gramUnit(with: .kilo), from: start, to: now)
            .map { HealthValuePoint(date: $0.date, value: $0.value) }
            .sorted { $0.date < $1.date }
    }

    func fetchWeeklyRunningHistory(weeks: Int) async throws -> [HealthValuePoint] {
        let now = Date()
        let currentWeekStart = startOfWeek(for: now)
        let start = calendar.date(byAdding: .weekOfYear, value: -weeks + 1, to: currentWeekStart) ?? currentWeekStart
        let workouts = try await runningWorkouts(from: start, to: now)

        return (0..<weeks).compactMap { offset in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: offset, to: start),
                  let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart)
            else { return nil }

            let distance = workouts
                .filter { $0.startDate >= weekStart && $0.startDate < weekEnd }
                .compactMap(workoutDistanceKm)
                .reduce(0, +)

            return HealthValuePoint(date: weekStart, value: distance)
        }
    }

    func fetchMonthlyRunningHistory(months: Int) async throws -> [HealthValuePoint] {
        let now = Date()
        let currentMonthComponents = calendar.dateComponents([.year, .month], from: now)
        let currentMonthStart = calendar.date(from: currentMonthComponents) ?? calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .month, value: -months + 1, to: currentMonthStart) ?? currentMonthStart
        let workouts = try await runningWorkouts(from: start, to: now)

        return (0..<months).compactMap { offset in
            guard let monthStart = calendar.date(byAdding: .month, value: offset, to: start),
                  let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)
            else { return nil }

            let distance = workouts
                .filter { $0.startDate >= monthStart && $0.startDate < monthEnd }
                .compactMap(workoutDistanceKm)
                .reduce(0, +)

            return HealthValuePoint(date: monthStart, value: distance)
        }
    }

    func fetchHeartRateSamples(days: Int) async throws -> [HeartRateSample] {
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -days + 1, to: calendar.startOfDay(for: now)) ?? now
        return try await quantitySamples(.heartRate, unit: .count().unitDivided(by: .minute()), from: start, to: now)
            .map { HeartRateSample(date: $0.date, value: $0.value) }
            .sorted { $0.date < $1.date }
    }

    func fetchMaxHeartRate() async throws -> Double {
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -365, to: now) ?? now
        let samples = try await quantitySamples(.heartRate, unit: .count().unitDivided(by: .minute()), from: start, to: now)
        let observedMax = samples.map(\.value).max()
        return min(max(observedMax ?? 190, 160), 210)
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]

        [
            .stepCount,
            .activeEnergyBurned,
            .appleExerciseTime,
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .bodyMass,
            .runningSpeed,
            .runningPower,
            .runningStrideLength,
            .runningGroundContactTime,
            .runningVerticalOscillation
        ].compactMap { quantityType($0) }.forEach { types.insert($0) }

        return types
    }

    private func quantityType(_ identifier: HKQuantityTypeIdentifier) -> HKQuantityType? {
        HKQuantityType.quantityType(forIdentifier: identifier)
    }

    private func sumQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> Double {
        guard let type = quantityType(identifier) else {
            throw HealthKitServiceError.missingType(identifier.rawValue)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }

            healthStore.execute(query)
        }
    }

    private func averageQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> Double? {
        guard let type = quantityType(identifier) else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: unit))
            }

            healthStore.execute(query)
        }
    }

    private func latestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> (value: Double, date: Date)? {
        guard let type = quantityType(identifier) else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: (sample.quantity.doubleValue(for: unit), sample.endDate))
            }

            healthStore.execute(query)
        }
    }

    private func nearestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, near date: Date, toleranceDays: Int) async throws -> (value: Double, date: Date)? {
        let start = calendar.date(byAdding: .day, value: -toleranceDays, to: date) ?? date
        let end = calendar.date(byAdding: .day, value: toleranceDays, to: date) ?? date
        guard let type = quantityType(identifier) else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 30, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let nearest = samples?
                    .compactMap { $0 as? HKQuantitySample }
                    .min { abs($0.endDate.timeIntervalSince(date)) < abs($1.endDate.timeIntervalSince(date)) }

                guard let sample = nearest else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: (sample.quantity.doubleValue(for: unit), sample.endDate))
            }

            healthStore.execute(query)
        }
    }

    private func quantitySamples(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> [(value: Double, date: Date)] {
        guard let type = quantityType(identifier) else { return [] }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let values = samples?
                    .compactMap { $0 as? HKQuantitySample }
                    .map { (value: $0.quantity.doubleValue(for: unit), date: $0.endDate) } ?? []

                continuation.resume(returning: values)
            }

            healthStore.execute(query)
        }
    }

    private func runningWorkouts(from start: Date, to end: Date) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let datePredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, runningPredicate])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }

            healthStore.execute(query)
        }
    }

    private func runningDistance(from start: Date, to end: Date) async throws -> Double {
        let workouts = try await runningWorkouts(from: start, to: end)
        return workouts.compactMap(workoutDistanceKm).reduce(0, +)
    }

    private func workoutDistanceKm(_ workout: HKWorkout) -> Double? {
        guard let meters = workout.totalDistance?.doubleValue(for: .meter()) else {
            return nil
        }

        return meters / 1000
    }

    private func hrvState(sevenDayAverage: Double?, baseline: Double?) -> HRVState {
        guard let sevenDayAverage, let baseline, baseline > 0 else { return .noData }
        if sevenDayAverage >= baseline * 1.10 { return .aboveBaseline }
        if sevenDayAverage < baseline * 0.90 { return .belowBaseline }
        return .normal
    }

    private func paceString(fromMetersPerSecond speed: Double?) -> String? {
        guard let speed, speed > 0 else { return nil }
        let secondsPerKm = 1000 / speed
        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    private func startOfWeek(for date: Date) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: dayStart)
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: dayStart) ?? dayStart
    }
}
