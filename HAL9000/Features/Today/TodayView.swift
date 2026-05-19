import Charts
import SwiftUI

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    switch viewModel.state {
                    case .idle, .loading:
                        loadingView

                    case .requestingPermission:
                        loadingView

                    case .permissionRequired:
                        HealthPermissionView {
                            Task { await viewModel.requestHealthAuthorization() }
                        }

                    case .loaded, .partialData:
                        if let snapshot = viewModel.snapshot {
                            TodayHealthDashboard(snapshot: snapshot)
                        } else {
                            loadingView
                        }

                    case .failed(let message):
                        errorView(message)
                    }

                    Color.clear.frame(height: 118)
                }
                .padding(.horizontal, 20)
                .padding(.top, 58)
            }
            .navigationDestination(for: TodayDetailRoute.self) { route in
                if let snapshot = viewModel.snapshot {
                    TodayMetricDetailView(route: route, snapshot: snapshot)
                } else {
                    loadingView
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .background {
                AppBackground()
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [
                        AppColor.heroBackground,
                        AppColor.heroBackground.opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 72)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
        .supportsSwipeBack()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(AppColor.pageTitle)
                Text(Date.now.formatted(date: .long, time: .omitted))
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 38, height: 38)
                    .background(AppColor.controlBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(AppColor.accent)
            Text("正在读取 Apple 健康")
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private func errorView(_ message: String) -> some View {
        TodayCard {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(AppColor.warning)
                Text("读取 Apple 健康失败")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.pageTitle)
                Text(message)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                PrimaryButton("重试") {
                    Task { await viewModel.load() }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private enum TodayDetailRoute: String, Hashable {
    case readiness
    case trainingLoad
    case hrv
    case bodyMass
    case weeklyRunning
    case monthlyRunning

    var title: String {
        switch self {
        case .readiness: return "状态稳定"
        case .trainingLoad: return "训练负荷"
        case .hrv: return "HRV 状态"
        case .bodyMass: return "体重"
        case .weeklyRunning: return "周跑量"
        case .monthlyRunning: return "月跑量"
        }
    }
}

private enum DetailRange: Int, CaseIterable, Identifiable {
    case seven = 7
    case thirty = 30
    case sixty = 60
    case ninety = 90

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .seven: return "7天"
        case .thirty: return "30天"
        case .sixty: return "60天"
        case .ninety: return "90天"
        }
    }
}

private struct TodayHealthDashboard: View {
    let snapshot: TodayHealthSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NavigationLink(value: TodayDetailRoute.readiness) {
                readinessCard
            }
            .buttonStyle(.plain)

            NavigationLink {
                TodayWorkoutListView(workouts: snapshot.todayActivity.workouts)
            } label: {
                todayActivityCard
            }
            .buttonStyle(.plain)

            NavigationLink(value: TodayDetailRoute.trainingLoad) {
                loadCard
            }
            .buttonStyle(.plain)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                NavigationLink(value: TodayDetailRoute.hrv) {
                    HealthMetricCard(
                        title: "HRV 状态",
                        value: snapshot.hrv.latestMs.map { String(format: "%.0f ms", $0) } ?? "--",
                        subtitle: "\(snapshot.hrv.state.title) · \(snapshot.hrv.state.guidance)",
                        systemImage: "waveform.path.ecg",
                        tint: tint(for: snapshot.hrv.state)
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: TodayDetailRoute.bodyMass) {
                    HealthMetricCard(
                        title: "体重",
                        value: snapshot.bodyMass.latestKg.map { String(format: "%.1f kg", $0) } ?? "--",
                        subtitle: bodyMassSubtitle,
                        systemImage: "scalemass",
                        tint: AppColor.accent
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: TodayDetailRoute.weeklyRunning) {
                    HealthMetricCard(
                        title: "周跑量",
                        value: snapshot.weeklyRunning.displayValue,
                        subtitle: snapshot.weeklyRunning.subtitle,
                        systemImage: "calendar.badge.clock",
                        tint: AppColor.success
                    )
                }
                .buttonStyle(.plain)

                NavigationLink(value: TodayDetailRoute.monthlyRunning) {
                    HealthMetricCard(
                        title: "月跑量",
                        value: snapshot.monthlyRunning.displayValue,
                        subtitle: snapshot.monthlyRunning.subtitle,
                        systemImage: "calendar",
                        tint: AppColor.warning
                    )
                }
                .buttonStyle(.plain)
            }

            runningMetricsCard
        }
    }

    private var readinessCard: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.loadBalance.title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColor.textPrimary)
                        Text(snapshot.loadBalance.guidance)
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    Spacer()

                    Image(systemName: readinessIcon)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(readinessTint)
                }

                HStack(spacing: 10) {
                    compactLoadPill(snapshot.shortTermLoad)
                    compactLoadPill(snapshot.longTermLoad)
                }
            }
        }
    }

    private var loadCard: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("训练负荷")
                        .font(AppTypography.title3)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }

                HStack(spacing: 12) {
                    loadColumn(snapshot.shortTermLoad)
                    Divider()
                        .background(AppColor.divider)
                    loadColumn(snapshot.longTermLoad)
                }
            }
        }
    }

    private var todayActivityCard: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("今日运动")
                        .font(AppTypography.title3)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text("\(snapshot.todayActivity.workouts.count) 次")
                        .font(AppTypography.captionBold)
                        .foregroundStyle(AppColor.accent)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(String(format: "%.0f", snapshot.todayActivity.exerciseMinutes))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                    Text("分钟")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                }

                HStack(spacing: 10) {
                    smallStat("能量", String(format: "%.0f kcal", snapshot.todayActivity.activeEnergyKcal))
                    smallStat("步数", String(format: "%.0f", snapshot.todayActivity.steps))
                    smallStat("跑步", String(format: "%.1f km", snapshot.todayActivity.runningDistanceKm))
                }
            }
        }
    }

    private var runningMetricsCard: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("跑步关键指标")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColor.textPrimary)

                VStack(spacing: 10) {
                    metricRow("最近配速", snapshot.runningKeyMetrics.latestPace ?? "--")
                    metricRow("平均心率", snapshot.runningKeyMetrics.averageHeartRate.map { String(format: "%.0f bpm", $0) } ?? "--")
                    metricRow("静息心率", snapshot.runningKeyMetrics.restingHeartRate.map { String(format: "%.0f bpm", $0) } ?? "--")
                    metricRow("跑步功率", snapshot.runningKeyMetrics.runningPower.map { String(format: "%.0f W", $0) } ?? "--")
                    metricRow("步幅", snapshot.runningKeyMetrics.strideLengthCm.map { String(format: "%.0f cm", $0) } ?? "--")
                    metricRow("触地时间", snapshot.runningKeyMetrics.groundContactTimeMs.map { String(format: "%.0f ms", $0) } ?? "--")
                    metricRow("垂直振幅", snapshot.runningKeyMetrics.verticalOscillationCm.map { String(format: "%.1f cm", $0) } ?? "--")
                }
            }
        }
    }

    private var bodyMassSubtitle: String {
        guard let trend = snapshot.bodyMass.trend30dKg else {
            return "最近一次记录"
        }

        if trend == 0 {
            return "30天持平"
        }

        let sign = trend > 0 ? "+" : ""
        return "30天 \(sign)\(String(format: "%.1f", trend)) kg"
    }

    private var readinessIcon: String {
        switch snapshot.loadBalance {
        case .fresh: return "bolt.heart"
        case .productive: return "checkmark.circle.fill"
        case .strained: return "exclamationmark.triangle.fill"
        case .detraining: return "arrow.down.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var readinessTint: Color {
        switch snapshot.loadBalance {
        case .fresh, .productive: return AppColor.success
        case .strained: return AppColor.warning
        case .detraining, .unknown: return AppColor.textTertiary
        }
    }

    private func compactLoadPill(_ load: TrainingLoadMetric) -> some View {
        HStack(spacing: 6) {
            Text(load.label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textSecondary)
            Text(load.displayValue)
                .font(AppTypography.captionBold)
                .foregroundStyle(AppColor.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppColor.controlBackground)
        .overlay {
            Capsule()
                .stroke(AppColor.divider.opacity(0.62), lineWidth: 1)
        }
        .clipShape(Capsule())
    }

    private func loadColumn(_ load: TrainingLoadMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(load.label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textSecondary)
            Text(load.displayValue)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
            Text(load.subtitle)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func smallStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textTertiary)
            Text(value)
                .font(AppTypography.captionBold)
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppColor.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            Text(value)
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textPrimary)
        }
    }

    private func tint(for state: HRVState) -> Color {
        switch state {
        case .aboveBaseline, .normal: return AppColor.success
        case .belowBaseline: return AppColor.warning
        case .noData: return AppColor.textTertiary
        }
    }
}

private struct TodayMetricDetailView: View {
    let route: TodayDetailRoute
    let snapshot: TodayHealthSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var range: DetailRange = .thirty

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                detailHeader

                switch route {
                case .readiness:
                    TSBDetailView(snapshot: snapshot)
                case .trainingLoad:
                    rangedPicker
                    trainingLoadDetail
                case .hrv:
                    rangedPicker
                    hrvDetail
                case .bodyMass:
                    rangedPicker
                    bodyMassDetail
                case .weeklyRunning:
                    weeklyRunningDetail
                case .monthlyRunning:
                    monthlyRunningDetail
                }

                Color.clear.frame(height: 118)
            }
            .padding(.horizontal, 20)
            .padding(.top, 58)
        }
        .toolbar(.hidden, for: .navigationBar)
        .background { AppBackground() }
        .supportsSwipeBack()
    }

    private var detailHeader: some View {
        HStack(alignment: .center) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(AppColor.controlBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(route.title)
                    .font(AppTypography.title)
                    .foregroundStyle(AppColor.pageTitle)
                Text("Apple 健康趋势")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()
        }
    }

    private var rangedPicker: some View {
        Picker("时间范围", selection: $range) {
            ForEach(DetailRange.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private var readinessDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            TodayCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(snapshot.loadBalance.title)
                        .font(AppTypography.title2)
                        .foregroundStyle(AppColor.textPrimary)
                    Text(readinessExplanation)
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            TodayCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("状态变化")
                        .font(AppTypography.title3)
                        .foregroundStyle(AppColor.textPrimary)
                    readinessChart
                        .frame(height: 210)
                }
            }

            TodayCard {
                VStack(alignment: .leading, spacing: 10) {
                    detailRow("短期负荷", snapshot.shortTermLoad.displayValue, "近 7 天训练压力")
                    detailRow("长期负荷", snapshot.longTermLoad.displayValue, "近 6 周训练基础")
                    detailRow("判断规则", readinessRule, "短期/长期负荷的差值和比例")
                }
            }
        }
    }

    private var trainingLoadDetail: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("短期 / 长期负荷")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColor.textPrimary)
                loadChart(points: filteredLoadHistory)
                    .frame(height: 240)
                detailLegend
            }
        }
    }

    private var hrvDetail: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("正常区间与 HRV 曲线")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColor.textPrimary)
                hrvChart(points: filteredValues(snapshot.hrvHistory))
                    .frame(height: 240)
                detailRow("正常区间", hrvNormalRangeText, "基于 28 天基线的 ±10%")
            }
        }
    }

    private var bodyMassDetail: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("体重趋势")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColor.textPrimary)
                valueLineChart(points: filteredValues(snapshot.bodyMassHistory), unit: "kg", tint: AppColor.accent)
                    .frame(height: 240)
                detailRow("最新体重", snapshot.bodyMass.latestKg.map { String(format: "%.1f kg", $0) } ?? "--", "Apple 健康最近一次记录")
            }
        }
    }

    private var weeklyRunningDetail: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("自然周跑量")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColor.textPrimary)
                barChart(points: snapshot.weeklyRunningHistory, unit: "km", tint: AppColor.success)
                    .frame(height: 240)
                detailRow("本周", snapshot.weeklyRunning.displayValue, "周一到周日，只统计跑步运动")
            }
        }
    }

    private var monthlyRunningDetail: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("自然月跑量")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColor.textPrimary)
                barChart(points: snapshot.monthlyRunningHistory, unit: "km", tint: AppColor.warning)
                    .frame(height: 240)
                detailRow("本月", snapshot.monthlyRunning.displayValue, "自然月累计，只统计跑步运动")
            }
        }
    }

    private var readinessChart: some View {
        let points = snapshot.loadHistory.compactMap { point -> HealthValuePoint? in
            guard let short = point.shortTermLoad, let long = point.longTermLoad, long > 0 else { return nil }
            return HealthValuePoint(date: point.date, value: short / long)
        }

        return ChartOrEmpty(points: points) {
            Chart(points) { point in
                RectangleMark(
                    xStart: .value("开始", point.date),
                    xEnd: .value("结束", point.date.addingTimeInterval(24 * 60 * 60)),
                    yStart: .value("下限", 0.65),
                    yEnd: .value("上限", 1.35)
                )
                .foregroundStyle(AppColor.success.opacity(0.12))

                LineMark(
                    x: .value("日期", point.date),
                    y: .value("负荷比", point.value)
                )
                .foregroundStyle(AppColor.accent)
                .interpolationMethod(.catmullRom)

                RuleMark(y: .value("稳定线", 1.0))
                    .foregroundStyle(AppColor.textSecondary.opacity(0.35))
            }
            .chartYAxisLabel("短期/长期")
        }
    }

    private func loadChart(points: [TrainingLoadHistoryPoint]) -> some View {
        ChartOrEmpty(points: points.filter { $0.shortTermLoad != nil || $0.longTermLoad != nil }) {
            Chart {
                ForEach(points) { point in
                    if let shortTermLoad = point.shortTermLoad {
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("负荷", shortTermLoad),
                            series: .value("类型", "短期负荷")
                        )
                        .foregroundStyle(AppColor.accent)
                        .interpolationMethod(.catmullRom)
                    }

                    if let longTermLoad = point.longTermLoad {
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value("负荷", longTermLoad),
                            series: .value("类型", "长期负荷")
                        )
                        .foregroundStyle(AppColor.success)
                        .interpolationMethod(.catmullRom)
                    }
                }
            }
        }
    }

    private func hrvChart(points: [HealthValuePoint]) -> some View {
        ChartOrEmpty(points: points) {
            Chart {
                if let baseline = snapshot.hrv.baselineMs {
                    RectangleMark(
                        xStart: .value("开始", points.first?.date ?? Date()),
                        xEnd: .value("结束", points.last?.date ?? Date()),
                        yStart: .value("下限", baseline * 0.9),
                        yEnd: .value("上限", baseline * 1.1)
                    )
                    .foregroundStyle(AppColor.success.opacity(0.12))
                    RuleMark(y: .value("基线", baseline))
                        .foregroundStyle(AppColor.textSecondary.opacity(0.35))
                }

                ForEach(points) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("HRV", point.value)
                    )
                    .foregroundStyle(AppColor.success)
                    .interpolationMethod(.catmullRom)
                }
            }
        }
    }

    private func valueLineChart(points: [HealthValuePoint], unit: String, tint: Color) -> some View {
        ChartOrEmpty(points: points) {
            Chart(points) { point in
                LineMark(
                    x: .value("日期", point.date),
                    y: .value(unit, point.value)
                )
                .foregroundStyle(tint)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("日期", point.date),
                    y: .value(unit, point.value)
                )
                .foregroundStyle(tint)
            }
        }
    }

    private func barChart(points: [HealthValuePoint], unit: String, tint: Color) -> some View {
        ChartOrEmpty(points: points) {
            Chart(points) { point in
                BarMark(
                    x: .value("日期", point.date),
                    y: .value(unit, point.value)
                )
                .foregroundStyle(tint)
                .cornerRadius(5)
            }
        }
    }

    private var filteredLoadHistory: [TrainingLoadHistoryPoint] {
        filterByRange(snapshot.loadHistory)
    }

    private func filteredValues(_ points: [HealthValuePoint]) -> [HealthValuePoint] {
        filterByRange(points)
    }

    private func filterByRange<T>(_ items: [T]) -> [T] {
        guard let lastDate = items.compactMap({ item -> Date? in
            if let point = item as? HealthValuePoint { return point.date }
            if let point = item as? TrainingLoadHistoryPoint { return point.date }
            return nil
        }).max(),
              let start = Calendar.current.date(byAdding: .day, value: -range.rawValue + 1, to: lastDate)
        else { return items }

        return items.filter { item in
            if let point = item as? HealthValuePoint { return point.date >= start }
            if let point = item as? TrainingLoadHistoryPoint { return point.date >= start }
            return true
        }
    }

    private var readinessExplanation: String {
        switch snapshot.loadBalance {
        case .productive:
            return "短期负荷接近长期负荷，说明近期训练刺激和既有训练基础匹配，可以正常训练。"
        case .fresh:
            return "短期负荷低于长期负荷，身体相对轻松，适合安排质量训练或逐步增加刺激。"
        case .strained:
            return "短期负荷明显高于长期负荷，近期压力偏高，建议降低强度或安排恢复。"
        case .detraining:
            return "短期负荷明显低于长期负荷，训练刺激下降，建议逐步恢复跑量。"
        case .unknown:
            return "当前跑步数据不足，完成更多训练后会生成更可靠的判断。"
        }
    }

    private var readinessRule: String {
        guard let short = snapshot.shortTermLoad.value, let long = snapshot.longTermLoad.value, long > 0 else { return "数据不足" }
        return String(format: "%.0f / %.0f = %.2f", short, long, short / long)
    }

    private var hrvNormalRangeText: String {
        guard let baseline = snapshot.hrv.baselineMs else { return "--" }
        return String(format: "%.0f-%.0f ms", baseline * 0.9, baseline * 1.1)
    }

    private var detailLegend: some View {
        HStack(spacing: 14) {
            legendDot("短期负荷", AppColor.accent)
            legendDot("长期负荷", AppColor.success)
        }
    }

    private func legendDot(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private func detailRow(_ title: String, _ value: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Text(value)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.textPrimary)
            }
            Text(subtitle)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
    }
}

private struct ChartOrEmpty<Content: View, Data>: View {
    let points: [Data]
    let content: Content

    init(points: [Data], @ViewBuilder content: () -> Content) {
        self.points = points
        self.content = content()
    }

    var body: some View {
        if points.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                Text("暂无足够历史数据")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
        }
    }
}

private struct HealthMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColor.textTertiary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 124, alignment: .top)
        }
    }
}

private struct HealthPermissionView: View {
    let request: () -> Void

    var body: some View {
        TodayCard {
            VStack(spacing: 16) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                Text("连接 Apple 健康")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColor.textPrimary)
                Text("读取跑步、HRV、体重和运动记录，用来生成今日训练状态。")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                PrimaryButton("授权 Apple 健康", systemImage: "heart.fill", action: request)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 80)
    }
}

struct TodayCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(AppColor.contentBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(AppColor.divider.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 8)
    }
}
