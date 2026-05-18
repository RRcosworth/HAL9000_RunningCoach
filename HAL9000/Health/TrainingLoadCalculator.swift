import Foundation

struct TrainingLoadResult: Equatable {
    let shortTerm: TrainingLoadMetric
    let longTerm: TrainingLoadMetric
    let balance: LoadBalanceState
}

struct TrainingLoadCalculator {
    func calculate(days: [RunningLoadDay]) -> TrainingLoadResult {
        let sortedDays = days.sorted { $0.date > $1.date }
        let recentSeven = Array(sortedDays.prefix(7))
        let recentFortyTwo = Array(sortedDays.prefix(42))

        let atl = weightedAverageLoad(days: recentSeven, minimumDays: 3)
        let ctl = weightedAverageLoad(days: recentFortyTwo, minimumDays: 14)

        let balance = loadBalance(shortTerm: atl, longTerm: ctl)

        return TrainingLoadResult(
            shortTerm: TrainingLoadMetric(
                value: atl,
                label: "短期负荷",
                trend: trend(for: recentSeven),
                subtitle: "近7天"
            ),
            longTerm: TrainingLoadMetric(
                value: ctl,
                label: "长期负荷",
                trend: trend(for: recentFortyTwo),
                subtitle: ctl == nil ? "需要14天以上数据" : "近6周"
            ),
            balance: balance
        )
    }

    func calculateTSB(days: [RunningLoadDay]) -> TSBResult {
        let dailyTSS = days.map { day in
            (date: day.date, tss: dailyLoad(day))
        }
        return TSBCalculator().calculate(dailyTSS: dailyTSS)
    }

    func calculateHistory(days: [RunningLoadDay], displayDays: Int) -> [TrainingLoadHistoryPoint] {
        let calendar = Calendar.current
        let ascendingDays = days.sorted { $0.date < $1.date }
        guard let latestDate = ascendingDays.last?.date else { return [] }
        let firstDisplayDate = calendar.date(byAdding: .day, value: -displayDays + 1, to: calendar.startOfDay(for: latestDate)) ?? latestDate

        return ascendingDays
            .filter { $0.date >= firstDisplayDate }
            .map { day in
                let availableDays = ascendingDays.filter { $0.date <= day.date }.sorted { $0.date > $1.date }
                let recentSeven = Array(availableDays.prefix(7))
                let recentFortyTwo = Array(availableDays.prefix(42))
                let shortTerm = weightedAverageLoad(days: recentSeven, minimumDays: 3)
                let longTerm = weightedAverageLoad(days: recentFortyTwo, minimumDays: 14)

                return TrainingLoadHistoryPoint(
                    date: day.date,
                    shortTermLoad: shortTerm,
                    longTermLoad: longTerm,
                    balance: loadBalance(shortTerm: shortTerm, longTerm: longTerm)
                )
            }
    }

    private func weightedAverageLoad(days: [RunningLoadDay], minimumDays: Int) -> Double? {
        guard days.count >= minimumDays else { return nil }

        var weightedLoad = 0.0
        var totalWeight = 0.0

        for (index, day) in days.enumerated() {
            let weight = pow(0.85, Double(index))
            weightedLoad += dailyLoad(day) * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else { return nil }
        return weightedLoad / totalWeight
    }

    func dailyLoad(_ day: RunningLoadDay) -> Double {
        var load = day.runningDistanceKm * 10 + day.exerciseMinutes * 0.5

        if let averageHeartRate = day.averageHeartRate,
           let restingHeartRate = day.restingHeartRate,
           restingHeartRate > 0 {
            let heartRateFactor = min(max(averageHeartRate / restingHeartRate, 1.0), 2.2)
            load = day.runningDistanceKm * 10 * heartRateFactor + day.exerciseMinutes * 0.3
        }

        return load
    }

    private func loadBalance(shortTerm: Double?, longTerm: Double?) -> LoadBalanceState {
        guard let shortTerm, let longTerm, longTerm > 0 else { return .unknown }

        let balance = shortTerm - longTerm
        let ratio = shortTerm / longTerm

        if shortTerm < longTerm * 0.65 {
            return .detraining
        }

        if balance > 15 || ratio > 1.35 {
            return .strained
        }

        if balance < -10 {
            return .fresh
        }

        return .productive
    }

    private func trend(for days: [RunningLoadDay]) -> MetricTrend {
        guard days.count >= 6 else { return .unknown }

        let firstHalf = days.prefix(days.count / 2).map(dailyLoad).reduce(0, +)
        let secondHalf = days.suffix(days.count / 2).map(dailyLoad).reduce(0, +)

        if firstHalf > secondHalf * 1.12 { return .up }
        if firstHalf < secondHalf * 0.88 { return .down }
        return .stable
    }
}
