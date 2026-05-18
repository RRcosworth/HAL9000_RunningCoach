import Charts
import SwiftUI

struct TSBDetailView: View {
    let snapshot: TodayHealthSnapshot
    @State private var range: TSBRange = .thirty

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            fitnessCard
            loadFocusCard
            loadRatioCard
            heartRateIntensityCard
        }
    }

    private var fitnessCard: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 16) {
                cardHeader("Fitness", subtitle: snapshot.tsbData?.state.guidance ?? "需要更多训练数据")

                if let tsbData = snapshot.tsbData {
                    HStack(spacing: 10) {
                        tsbStat("CTL", value: tsbData.ctl, label: "Fitness", color: AppColor.tsbFitness)
                        tsbStat("ATL", value: tsbData.atl, label: "Fatigue", color: AppColor.tsbFatigue)
                        tsbStat("TSB", value: tsbData.tsb, label: "Form", color: AppColor.tsbForm, showSign: true)
                    }

                    Picker("时间范围", selection: $range) {
                        ForEach(TSBRange.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    tsbChart(points: filteredTSBHistory(tsbData.history))
                        .frame(height: 230)

                    HStack(spacing: 14) {
                        legend("CTL", AppColor.tsbFitness)
                        legend("ATL", AppColor.tsbFatigue)
                        legend("TSB", AppColor.tsbForm)
                    }
                } else {
                    emptyState("暂无 TSB 趋势数据")
                }
            }
        }
    }

    private var loadFocusCard: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 16) {
                cardHeader("Training Load Focus", subtitle: snapshot.loadFocus?.period ?? "近 28 天")

                if let focus = snapshot.loadFocus, focus.dailyBreakdown.isEmpty == false {
                    VStack(spacing: 10) {
                        focusRow("Anaerobic", value: focus.anaerobic, percent: focus.anaerobicPercent, color: AppColor.anaerobic)
                        focusRow("High Aerobic", value: focus.highAerobic, percent: focus.highAerobicPercent, color: AppColor.highAerobic)
                        focusRow("Low Aerobic", value: focus.lowAerobic, percent: focus.lowAerobicPercent, color: AppColor.lowAerobic)
                    }

                    Text("Daily Training Load Focus")
                        .font(AppTypography.captionBold)
                        .foregroundStyle(AppColor.textSecondary)

                    focusChart(focus.dailyBreakdown)
                        .frame(height: 180)

                    Text("Training Method: % Max HR")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColor.textTertiary)
                } else {
                    emptyState("暂无心率负荷分布")
                }
            }
        }
    }

    private var loadRatioCard: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 16) {
                cardHeader("Training Load Ratio", subtitle: ratioExplanation)

                if let tsbData = snapshot.tsbData {
                    let ratio = currentRatio(tsbData)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: "%.2f", ratio))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(ratioColor(ratio))
                        ratioGauge(ratio: ratio)
                    }

                    Text("Daily Training Load Ratio")
                        .font(AppTypography.captionBold)
                        .foregroundStyle(AppColor.textSecondary)

                    ratioChart(points: filteredTSBHistory(tsbData.history))
                        .frame(height: 190)
                } else {
                    emptyState("暂无负荷比例历史")
                }
            }
        }
    }

    private var heartRateIntensityCard: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 16) {
                cardHeader("Heart Rate Intensity", subtitle: snapshot.heartRateDistribution?.period ?? "近 7 天")

                if let distribution = snapshot.heartRateDistribution, distribution.totalMinutes > 0 {
                    stackedZoneBar(distribution.zones)
                        .frame(height: 12)

                    VStack(spacing: 10) {
                        ForEach(distribution.zones) { zone in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(zoneColor(zone.zone))
                                    .frame(width: 9, height: 9)
                                Text(zone.name)
                                    .font(AppTypography.captionBold)
                                    .foregroundStyle(AppColor.textPrimary)
                                    .frame(width: 80, alignment: .leading)
                                Text(zone.rangeText)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                                Spacer()
                                Text(String(format: "%.0f%%", zone.percentage))
                                    .font(AppTypography.captionBold)
                                    .foregroundStyle(AppColor.textPrimary)
                                    .frame(width: 42, alignment: .trailing)
                                Text(formatMinutes(zone.minutes))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColor.textSecondary)
                                    .frame(width: 50, alignment: .trailing)
                            }
                        }
                    }

                    Text("Training Method: % Max HR")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColor.textTertiary)
                } else {
                    emptyState("暂无心率强度数据")
                }
            }
        }
    }

    private func tsbChart(points: [TSBDisplayData.TSBChartPoint]) -> some View {
        Group {
            if points.isEmpty {
                emptyState("暂无足够历史数据")
            } else {
                Chart {
                    ForEach(points) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("CTL", point.ctl)
                        )
                        .foregroundStyle(AppColor.tsbFitness.opacity(0.12))

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("CTL", point.ctl),
                            series: .value("Metric", "CTL")
                        )
                        .foregroundStyle(AppColor.tsbFitness)
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("ATL", point.atl),
                            series: .value("Metric", "ATL")
                        )
                        .foregroundStyle(AppColor.tsbFatigue)
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("TSB", point.tsb),
                            series: .value("Metric", "TSB")
                        )
                        .foregroundStyle(AppColor.tsbForm)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .interpolationMethod(.catmullRom)

                        RuleMark(y: .value("Neutral", 0))
                            .foregroundStyle(AppColor.textSecondary.opacity(0.28))
                    }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .chartYAxis { AxisMarks(position: .leading) }
            }
        }
    }

    private func focusChart(_ days: [DailyLoadFocus]) -> some View {
        Chart(days) { day in
            BarMark(
                x: .value("Date", day.date),
                yStart: .value("Low Start", 0),
                yEnd: .value("Low", day.lowAerobic)
            )
            .foregroundStyle(AppColor.lowAerobic)
            .cornerRadius(4)

            BarMark(
                x: .value("Date", day.date),
                yStart: .value("High Start", day.lowAerobic),
                yEnd: .value("High", day.lowAerobic + day.highAerobic)
            )
            .foregroundStyle(AppColor.highAerobic)
            .cornerRadius(4)

            BarMark(
                x: .value("Date", day.date),
                yStart: .value("Anaerobic Start", day.lowAerobic + day.highAerobic),
                yEnd: .value("Anaerobic", day.lowAerobic + day.highAerobic + day.anaerobic)
            )
            .foregroundStyle(AppColor.anaerobic)
            .cornerRadius(4)
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .chartYAxis { AxisMarks(position: .leading) }
    }

    private func ratioChart(points: [TSBDisplayData.TSBChartPoint]) -> some View {
        let ratioPoints = points.compactMap { point -> HealthValuePoint? in
            guard point.ctl > 0 else { return nil }
            return HealthValuePoint(date: point.date, value: point.atl / point.ctl)
        }

        return Group {
            if ratioPoints.isEmpty {
                emptyState("暂无足够历史数据")
            } else {
                Chart(ratioPoints) { point in
                    RectangleMark(
                        xStart: .value("Start", point.date),
                        xEnd: .value("End", point.date.addingTimeInterval(24 * 60 * 60)),
                        yStart: .value("Low", 0.8),
                        yEnd: .value("High", 1.1)
                    )
                    .foregroundStyle(AppColor.success.opacity(0.10))

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Ratio", point.value)
                    )
                    .foregroundStyle(AppColor.textPrimary)
                    .interpolationMethod(.catmullRom)

                    RuleMark(y: .value("Balance", 1.0))
                        .foregroundStyle(AppColor.textSecondary.opacity(0.30))
                }
                .chartYScale(domain: 0...max(1.8, (ratioPoints.map(\.value).max() ?? 1.2) + 0.2))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .chartYAxis { AxisMarks(position: .leading) }
            }
        }
    }

    private func ratioGauge(ratio: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [AppColor.lowAerobic, AppColor.success, AppColor.highAerobic, AppColor.error],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 9)
                .clipShape(Capsule())

                Circle()
                    .fill(AppColor.pageTitle)
                    .frame(width: 15, height: 15)
                    .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
                    .offset(x: max(0, min(geometry.size.width - 15, geometry.size.width * ratioPosition(ratio: ratio))))
            }
        }
        .frame(height: 18)
    }

    private func stackedZoneBar(_ zones: [HRZoneBreakdown]) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(zones) { zone in
                    Rectangle()
                        .fill(zoneColor(zone.zone))
                        .frame(width: max(1, geometry.size.width * zone.percentage / 100))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func cardHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.title3)
                .foregroundStyle(AppColor.textPrimary)
            Text(subtitle)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private func tsbStat(_ title: String, value: Double, label: String, color: Color, showSign: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textSecondary)
            Text(formatValue(value, showSign: showSign))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppColor.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func focusRow(_ title: String, value: Double, percent: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(AppTypography.captionBold)
                .foregroundStyle(AppColor.textPrimary)
                .frame(width: 94, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.controlBackground)
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * percent / 100)
                }
            }
            .frame(height: 8)
            Text(String(format: "%.0f%%", percent))
                .font(AppTypography.captionBold)
                .foregroundStyle(AppColor.textPrimary)
                .frame(width: 42, alignment: .trailing)
            Text(String(format: "%.0f", value))
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 34, alignment: .trailing)
        }
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private func emptyState(_ title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
            Text(title)
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func filteredTSBHistory(_ points: [TSBDisplayData.TSBChartPoint]) -> [TSBDisplayData.TSBChartPoint] {
        guard let lastDate = points.map(\.date).max(),
              let start = Calendar.current.date(byAdding: .day, value: -range.days + 1, to: lastDate)
        else { return points }
        return points.filter { $0.date >= start }
    }

    private func currentRatio(_ tsbData: TSBDisplayData) -> Double {
        guard tsbData.ctl > 0 else { return 0 }
        return tsbData.atl / tsbData.ctl
    }

    private var ratioExplanation: String {
        guard let tsbData = snapshot.tsbData else { return "ATL / CTL" }
        let ratio = currentRatio(tsbData)
        switch ratio {
        case ..<0.8: return "短期负荷低于长期基础"
        case ..<1.1: return "短期负荷与长期基础匹配"
        case ..<1.5: return "短期负荷偏高"
        default: return "短期负荷明显过高"
        }
    }

    private func ratioPosition(ratio: Double) -> Double {
        min(max((ratio - 0.5) / 1.2, 0), 1)
    }

    private func ratioColor(_ ratio: Double) -> Color {
        switch ratio {
        case ..<0.8: return AppColor.lowAerobic
        case ..<1.1: return AppColor.success
        case ..<1.5: return AppColor.highAerobic
        default: return AppColor.error
        }
    }

    private func zoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: return AppColor.tsbFitness
        case 2: return AppColor.success
        case 3: return AppColor.hrZone3
        case 4: return AppColor.highAerobic
        case 5: return AppColor.hrZone5
        default: return AppColor.textTertiary
        }
    }

    private func formatValue(_ value: Double, showSign: Bool = false) -> String {
        if showSign && value > 0 {
            return String(format: "+%.0f", value)
        }
        return String(format: "%.0f", value)
    }

    private func formatMinutes(_ minutes: Double) -> String {
        if minutes < 1 {
            return "<1m"
        }
        return "\(Int(minutes.rounded()))m"
    }
}

private enum TSBRange: Int, CaseIterable, Identifiable {
    case thirty = 30
    case sixWeeks = 42
    case threeMonths = 90
    case sixMonths = 180

    var id: Int { rawValue }
    var days: Int { rawValue }

    var title: String {
        switch self {
        case .thirty: return "30D"
        case .sixWeeks: return "6W"
        case .threeMonths: return "3M"
        case .sixMonths: return "6M"
        }
    }
}
