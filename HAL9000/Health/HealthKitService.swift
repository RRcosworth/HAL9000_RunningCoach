import Foundation
import CoreLocation
import HealthKit

protocol HealthKitServing {
    func requestAuthorization() async throws
    func authorizationState() async -> HealthAuthorizationState
    func fetchTodayActivity() async throws -> TodayActivityMetric
    func fetchWeeklyRunningDistance() async throws -> RunningDistanceMetric
    func fetchMonthlyRunningDistance() async throws -> RunningDistanceMetric
    func fetchHRVMetric() async throws -> HRVMetric
    func fetchSleepMetric() async throws -> SleepMetric
    func fetchBodyMassMetric() async throws -> BodyMassMetric
    func fetchRunningKeyMetrics() async throws -> RunningKeyMetrics
    func fetchRunningLoadDays(days: Int) async throws -> [RunningLoadDay]
    func fetchHRVHistory(days: Int) async throws -> [HealthValuePoint]
    func fetchSleepScoreHistory(days: Int) async throws -> [HealthValuePoint]
    func fetchBodyMassHistory(days: Int) async throws -> [HealthValuePoint]
    func fetchWeeklyRunningHistory(weeks: Int) async throws -> [HealthValuePoint]
    func fetchMonthlyRunningHistory(months: Int) async throws -> [HealthValuePoint]
    func fetchHeartRateSamples(days: Int) async throws -> [HeartRateSample]
    func fetchMaxHeartRate() async throws -> Double
    func fetchRunningWorkoutSummaries(from start: Date, to end: Date) async throws -> [TodayWorkoutSummary]
    func fetchWorkoutDetail(id: String) async throws -> WorkoutDetail
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
    private let authorizationRequestVersion = 3
    private let authorizationRequestVersionKey = "healthKitAuthorizationRequestVersion"

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitServiceError.unavailable
        }

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
        return hasRequestedAuthorization ? .authorized : .notDetermined
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
        async let walkingRunningDistance = sumQuantity(.distanceWalkingRunning, unit: .meterUnit(with: .kilo), from: start, to: now)
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
            walkingDistanceKm: max(try await walkingRunningDistance - (try await runningDistance), 0),
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
            overnightAverageMs: try await overnightHRVAverage(reference: now),
            sevenDayAverageMs: sevenDayValue,
            baselineMs: baselineValue,
            state: hrvState(sevenDayAverage: sevenDayValue, baseline: baselineValue)
        )
    }

    func fetchSleepMetric() async throws -> SleepMetric {
        let interval = lastSleepWindow(reference: Date())
        let samples = try await sleepSamples(from: interval.start, to: interval.end)
        return sleepMetric(from: samples)
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
        let latestRun = try await runningWorkouts(from: thirtyDaysAgo, to: now).first

        async let restingHeartRate = latestQuantity(.restingHeartRate, unit: .count().unitDivided(by: .minute()), from: thirtyDaysAgo, to: now)
        let metricStart = latestRun?.startDate ?? thirtyDaysAgo
        let metricEnd = latestRun?.endDate ?? now
        async let averageHeartRate = averageQuantity(.heartRate, unit: .count().unitDivided(by: .minute()), from: metricStart, to: metricEnd)
        async let runningPower = latestQuantity(.runningPower, unit: .watt(), from: metricStart, to: metricEnd)
        async let runningSpeed = latestQuantity(.runningSpeed, unit: .meter().unitDivided(by: .second()), from: metricStart, to: metricEnd)
        async let strideLength = latestQuantity(.runningStrideLength, unit: .meterUnit(with: .centi), from: metricStart, to: metricEnd)
        async let contactTime = latestQuantity(.runningGroundContactTime, unit: .secondUnit(with: .milli), from: metricStart, to: metricEnd)
        async let verticalOscillation = latestQuantity(.runningVerticalOscillation, unit: .meterUnit(with: .centi), from: metricStart, to: metricEnd)

        let speedSample = try await runningSpeed
        let restingHeartRateSample = try await restingHeartRate
        let runningPowerSample = try await runningPower
        let strideLengthSample = try await strideLength
        let contactTimeSample = try await contactTime
        let verticalOscillationSample = try await verticalOscillation

        return RunningKeyMetrics(
            latestPace: latestRun.flatMap(workoutPaceString) ?? paceString(fromMetersPerSecond: speedSample?.value),
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

    func fetchSleepScoreHistory(days: Int) async throws -> [HealthValuePoint] {
        let now = Date()
        let today = calendar.startOfDay(for: now)
        var points: [HealthValuePoint] = []

        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -days + 1 + offset, to: today) else {
                continue
            }
            let interval = lastSleepWindow(reference: day.addingTimeInterval(12 * 60 * 60))
            let metric = sleepMetric(from: try await sleepSamples(from: interval.start, to: interval.end))
            guard let score = metric.score else { continue }
            points.append(HealthValuePoint(date: day, value: score))
        }

        return points
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

    func fetchRunningWorkoutSummaries(from start: Date, to end: Date) async throws -> [TodayWorkoutSummary] {
        let workouts = try await runningWorkouts(from: start, to: end)
        return workouts.map { workout in
            TodayWorkoutSummary(
                id: workout.uuid.uuidString,
                title: workout.workoutActivityType == .running ? "跑步" : "运动",
                startedAt: workout.startDate,
                durationMinutes: workout.duration / 60,
                distanceKm: workoutDistanceKm(workout)
            )
        }
    }

    func fetchWorkoutDetail(id: String) async throws -> WorkoutDetail {
        guard let uuid = UUID(uuidString: id),
              let workout = try await workout(id: uuid)
        else {
            throw HealthKitServiceError.missingType("Workout")
        }

        async let routePoints = workoutRoutePoints(for: workout)
        async let heartRateSamples = quantitySamples(
            .heartRate,
            unit: .count().unitDivided(by: .minute()),
            from: workout.startDate,
            to: workout.endDate
        )

        let samples = try await heartRateSamples
            .map { HeartRateSample(date: $0.date, value: $0.value) }
            .sorted { $0.date < $1.date }
        let points = try await routePoints
        let averageHeartRate = samples.isEmpty ? nil : samples.map(\.value).reduce(0, +) / Double(samples.count)

        return WorkoutDetail(
            id: workout.uuid.uuidString,
            title: workout.workoutActivityType == .running ? "跑步" : "运动",
            startedAt: workout.startDate,
            endedAt: workout.endDate,
            duration: workout.duration,
            distanceKm: workoutDistanceKm(workout),
            activeEnergyKcal: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
            averageHeartRate: averageHeartRate,
            maxHeartRate: samples.map(\.value).max(),
            route: points,
            heartRateSamples: samples,
            splits: workoutSplits(route: points, heartRateSamples: samples)
        )
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        types.insert(HKSeriesType.workoutRoute())

        [
            .stepCount,
            .activeEnergyBurned,
            .appleExerciseTime,
            .heartRate,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .bodyMass,
            .distanceWalkingRunning,
            .runningSpeed,
            .runningPower,
            .runningStrideLength,
            .runningGroundContactTime,
            .runningVerticalOscillation
        ].compactMap { quantityType($0) }.forEach { types.insert($0) }
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }

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

    private func sleepSamples(from start: Date, to end: Date) async throws -> [HKCategorySample] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }

        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
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

    private func workout(id: UUID) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObject(with: id)
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: samples?.first as? HKWorkout)
            }

            healthStore.execute(query)
        }
    }

    private func workoutRoutePoints(for workout: HKWorkout) async throws -> [WorkoutRoutePoint] {
        let routes = try await workoutRoutes(for: workout)
        var points: [WorkoutRoutePoint] = []

        for route in routes {
            let locations = try await locations(for: route)
            points.append(contentsOf: locations.map {
                WorkoutRoutePoint(
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude,
                    date: $0.timestamp
                )
            })
        }

        return points.sorted { $0.date < $1.date }
    }

    private func workoutRoutes(for workout: HKWorkout) async throws -> [HKWorkoutRoute] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForObjects(from: workout)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: samples as? [HKWorkoutRoute] ?? [])
            }

            healthStore.execute(query)
        }
    }

    private func locations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { continuation in
            var allLocations: [CLLocation] = []
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                allLocations.append(contentsOf: locations ?? [])

                if done {
                    continuation.resume(returning: allLocations)
                }
            }

            healthStore.execute(query)
        }
    }

    private func workoutSplits(route: [WorkoutRoutePoint], heartRateSamples: [HeartRateSample]) -> [WorkoutSplit] {
        guard route.count >= 2 else { return [] }

        var splits: [WorkoutSplit] = []
        var cumulativeDistance = 0.0
        var nextBoundary = 1.0
        var splitStartDate = route[0].date

        for index in 1..<route.count {
            let previous = route[index - 1]
            let current = route[index]
            let previousLocation = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
            let currentLocation = CLLocation(latitude: current.latitude, longitude: current.longitude)
            let segmentKm = currentLocation.distance(from: previousLocation) / 1000
            guard segmentKm > 0 else { continue }

            let segmentStartDistance = cumulativeDistance
            cumulativeDistance += segmentKm

            while cumulativeDistance >= nextBoundary {
                let ratio = min(max((nextBoundary - segmentStartDistance) / segmentKm, 0), 1)
                let boundaryDate = previous.date.addingTimeInterval(current.date.timeIntervalSince(previous.date) * ratio)
                let splitSamples = heartRateSamples.filter { $0.date >= splitStartDate && $0.date <= boundaryDate }
                let averageHeartRate = splitSamples.isEmpty ? nil : splitSamples.map(\.value).reduce(0, +) / Double(splitSamples.count)

                splits.append(
                    WorkoutSplit(
                        kilometer: Int(nextBoundary),
                        duration: boundaryDate.timeIntervalSince(splitStartDate),
                        averageHeartRate: averageHeartRate
                    )
                )

                splitStartDate = boundaryDate
                nextBoundary += 1
            }
        }

        return splits
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

    private func overnightHRVAverage(reference: Date) async throws -> Double? {
        let interval = lastSleepWindow(reference: reference)
        return try await averageQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: interval.start, to: interval.end)
    }

    private func lastSleepWindow(reference: Date) -> (start: Date, end: Date) {
        let dayStart = calendar.startOfDay(for: reference)
        let noon = dayStart.addingTimeInterval(12 * 60 * 60)

        if reference >= noon {
            let start = calendar.date(byAdding: .hour, value: -12, to: dayStart) ?? dayStart
            return (start, noon)
        }

        let previousDay = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
        return (previousDay.addingTimeInterval(12 * 60 * 60), dayStart.addingTimeInterval(12 * 60 * 60))
    }

    private func sleepMetric(from samples: [HKCategorySample]) -> SleepMetric {
        guard !samples.isEmpty else {
            return SleepMetric(score: nil, qualityTitle: "暂无数据", durationMinutes: nil, asleepMinutes: nil, awakeMinutes: nil, efficiency: nil)
        }

        var asleepMinutes = 0.0
        var awakeMinutes = 0.0
        var inBedMinutes = 0.0
        var restorativeMinutes = 0.0

        for sample in samples {
            let minutes = sample.endDate.timeIntervalSince(sample.startDate) / 60
            switch sample.value {
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                awakeMinutes += minutes
            case HKCategoryValueSleepAnalysis.inBed.rawValue:
                inBedMinutes += minutes
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                 HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                 HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                 HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                asleepMinutes += minutes
                if sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                    sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue {
                    restorativeMinutes += minutes
                }
            default:
                break
            }
        }

        let sleepSpan = max(samples.map(\.endDate).max()?.timeIntervalSince(samples.map(\.startDate).min() ?? Date()) ?? 0, 0) / 60
        let durationMinutes = max(asleepMinutes, 0)
        let denominator = max(inBedMinutes, sleepSpan, durationMinutes + awakeMinutes)
        let efficiency = denominator > 0 ? durationMinutes / denominator : nil

        guard durationMinutes > 0 else {
            return SleepMetric(score: nil, qualityTitle: "暂无睡眠", durationMinutes: nil, asleepMinutes: nil, awakeMinutes: awakeMinutes, efficiency: efficiency)
        }

        let durationScore = min(durationMinutes / 480, 1) * 50
        let efficiencyScore = min(max(((efficiency ?? 0) - 0.65) / 0.25, 0), 1) * 30
        let restorativeRatio = restorativeMinutes / durationMinutes
        let stageScore = min(restorativeRatio / 0.35, 1) * 20
        let score = min(max(durationScore + efficiencyScore + stageScore, 0), 100)

        return SleepMetric(
            score: score,
            qualityTitle: sleepQualityTitle(score),
            durationMinutes: durationMinutes,
            asleepMinutes: asleepMinutes,
            awakeMinutes: awakeMinutes,
            efficiency: efficiency
        )
    }

    private func sleepQualityTitle(_ score: Double) -> String {
        switch score {
        case 85...:
            return "优秀"
        case 70..<85:
            return "良好"
        case 55..<70:
            return "一般"
        default:
            return "欠佳"
        }
    }

    private func workoutPaceString(_ workout: HKWorkout) -> String? {
        guard let distanceKm = workoutDistanceKm(workout), distanceKm > 0 else { return nil }
        let secondsPerKm = workout.duration / distanceKm
        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
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
