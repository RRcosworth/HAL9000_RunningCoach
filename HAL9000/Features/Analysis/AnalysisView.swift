import Charts
import SwiftUI

struct AnalysisView: View {
    @StateObject private var viewModel = AnalysisViewModel()

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    switch viewModel.state {
                    case .idle, .loading:
                        loadingContent
                    case .permissionRequired:
                        permissionContent
                    case .loaded(let snapshot):
                        loadedContent(snapshot)
                    case .failed(let message):
                        errorContent(message)
                    }

                    Color.clear.frame(height: 126)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
        .task {
            await viewModel.load()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Analysis")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.pageTitle)
                Text("基于 42 天跑步数据和训练知识库")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 42, height: 42)
                    .background(AppColor.controlBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func loadedContent(_ snapshot: AnalysisSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            readinessCard(snapshot)
            volumeChart(snapshot)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                analysisMetricCard(title: "近7天", value: snapshot.sevenDayDistanceText, subtitle: "跑量", icon: "calendar.badge.clock", tint: AppColor.success)
                analysisMetricCard(title: "近42天", value: snapshot.fortyTwoDayDistanceText, subtitle: "跑量", icon: "chart.bar.fill", tint: AppColor.accent)
                analysisMetricCard(title: "周稳定性", value: snapshot.stabilityText, subtitle: snapshot.stabilitySubtitle, icon: "point.3.connected.trianglepath.dotted", tint: snapshot.stabilityTint)
                analysisMetricCard(title: "停跑", value: snapshot.daysSinceLastRunText, subtitle: "距上次跑步", icon: "figure.run.square.stack", tint: snapshot.consistencyTint)
            }

            insightSection(snapshot)
        }
    }

    private func readinessCard(_ snapshot: AnalysisSnapshot) -> some View {
        analysisCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: snapshot.statusIcon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(snapshot.statusTint)
                    .frame(width: 50, height: 50)
                    .background(snapshot.statusTint.opacity(0.14))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(snapshot.statusTitle)
                            .font(AppTypography.title3)
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        Text(snapshot.tsbText)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(snapshot.statusTint)
                    }

                    Text(snapshot.primaryGuidance)
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        loadPill("ATL", snapshot.shortTermLoad.displayValue, "近7天")
                        loadPill("CTL", snapshot.longTermLoad.displayValue, "近6周")
                        loadPill("TSB", snapshot.tsbText, "新鲜度")
                    }
                }
            }
        }
    }

    private func volumeChart(_ snapshot: AnalysisSnapshot) -> some View {
        analysisCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("跑量趋势")
                        .font(AppTypography.title3)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text("6 周")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Chart(snapshot.weeklyVolumes) { week in
                    BarMark(
                        x: .value("周", week.label),
                        y: .value("公里", week.distanceKm)
                    )
                    .foregroundStyle(week.isCurrent ? AppColor.accent : AppColor.success.opacity(0.72))
                    .cornerRadius(5)

                    RuleMark(y: .value("低跑量参考", snapshot.referenceMileageKm))
                        .foregroundStyle(AppColor.warning.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 190)

                Text("参考线按知识库的业余 5K 基础跑量下沿 40 km/week 展示；当前先作为训练量背景，不作为硬性目标。")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func insightSection(_ snapshot: AnalysisSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("知识库分析")

            ForEach(snapshot.insights) { insight in
                analysisCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: insight.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(insight.tint)
                            .frame(width: 40, height: 40)
                            .background(insight.tint.opacity(0.13))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 5) {
                            Text(insight.title)
                                .font(AppTypography.headline)
                                .foregroundStyle(AppColor.textPrimary)
                            Text(insight.message)
                                .font(AppTypography.footnote)
                                .foregroundStyle(AppColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 18)
                    .fill(index == 0 ? AppColor.controlBackground : AppColor.cardBackground)
                    .frame(height: index == 1 ? 240 : 118)
            }
        }
    }

    private var permissionContent: some View {
        analysisCard {
            VStack(spacing: 14) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 34))
                    .foregroundStyle(AppColor.accent)
                Text("需要 Apple 健康授权")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("Analysis 会读取跑步训练、运动时间和心率数据，用来分析跑量趋势、负荷和稳定性。")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                PrimaryButton("授权 Apple 健康") {
                    Task { await viewModel.requestAuthorization() }
                }
            }
        }
    }

    private func errorContent(_ message: String) -> some View {
        analysisCard {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 34))
                    .foregroundStyle(AppColor.warning)
                Text("分析暂不可用")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(message)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                PrimaryButton("重试") {
                    Task { await viewModel.refresh() }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.title3)
            .foregroundStyle(AppColor.pageTitle)
            .padding(.top, 2)
    }

    private func analysisMetricCard(title: String, value: String, subtitle: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColor.textPrimary)
                Text(subtitle)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.contentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func loadPill(_ title: String, _ value: String, _ subtitle: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textPrimary)
            Text(subtitle)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func analysisCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.contentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 8)
    }
}

@MainActor
final class AnalysisViewModel: ObservableObject {
    @Published var state: AnalysisViewState = .idle

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

    func load() async {
        state = .loading

        let authorization = await healthService.authorizationState()
        guard authorization == .authorized else {
            state = .permissionRequired
            return
        }

        await fetchAnalysis()
    }

    func refresh() async {
        await load()
    }

    func requestAuthorization() async {
        do {
            try await healthService.requestAuthorization()
            await fetchAnalysis()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func fetchAnalysis() async {
        state = .loading

        do {
            let days = try await healthService.fetchRunningLoadDays(days: 42)
            let loads = loadCalculator.calculate(days: days)
            let snapshot = AnalysisSnapshotBuilder(calendar: calendar).build(days: days, loads: loads)
            state = .loaded(snapshot)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

enum AnalysisViewState: Equatable {
    case idle
    case loading
    case permissionRequired
    case loaded(AnalysisSnapshot)
    case failed(String)
}

struct AnalysisSnapshot: Equatable {
    let generatedAt: Date
    let weeklyVolumes: [AnalysisWeekVolume]
    let shortTermLoad: TrainingLoadMetric
    let longTermLoad: TrainingLoadMetric
    let loadBalance: LoadBalanceState
    let sevenDayDistanceKm: Double
    let fortyTwoDayDistanceKm: Double
    let weeklyVariation: Double?
    let daysSinceLastRun: Int?
    let insights: [AnalysisInsight]
    let referenceMileageKm: Double

    var sevenDayDistanceText: String {
        String(format: "%.1f km", sevenDayDistanceKm)
    }

    var fortyTwoDayDistanceText: String {
        String(format: "%.0f km", fortyTwoDayDistanceKm)
    }

    var tsb: Double? {
        guard let short = shortTermLoad.value, let long = longTermLoad.value else { return nil }
        return long - short
    }

    var tsbText: String {
        guard let tsb else { return "--" }
        return String(format: "%+.0f", tsb)
    }

    var statusTitle: String {
        loadBalance.title
    }

    var primaryGuidance: String {
        loadBalance.guidance
    }

    var statusIcon: String {
        switch loadBalance {
        case .fresh: return "bolt.heart"
        case .productive: return "checkmark.seal"
        case .strained: return "exclamationmark.triangle"
        case .detraining: return "arrow.down.forward.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    var statusTint: Color {
        switch loadBalance {
        case .fresh: return AppColor.accent
        case .productive: return AppColor.success
        case .strained: return AppColor.warning
        case .detraining: return AppColor.textSecondary
        case .unknown: return AppColor.textTertiary
        }
    }

    var stabilityText: String {
        guard let weeklyVariation else { return "--" }
        return String(format: "%.0f%%", weeklyVariation * 100)
    }

    var stabilitySubtitle: String {
        guard let weeklyVariation else { return "需要更多周数据" }
        return weeklyVariation > 0.4 ? "波动偏大" : "较稳定"
    }

    var stabilityTint: Color {
        guard let weeklyVariation else { return AppColor.textTertiary }
        return weeklyVariation > 0.4 ? AppColor.warning : AppColor.success
    }

    var daysSinceLastRunText: String {
        guard let daysSinceLastRun else { return "--" }
        return "\(daysSinceLastRun) 天"
    }

    var consistencyTint: Color {
        guard let daysSinceLastRun else { return AppColor.textTertiary }
        return daysSinceLastRun > 2 ? AppColor.warning : AppColor.success
    }
}

struct AnalysisWeekVolume: Identifiable, Equatable {
    let id = UUID()
    let startDate: Date
    let label: String
    let distanceKm: Double
    let isCurrent: Bool
}

struct AnalysisInsight: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let icon: String
    let tint: Color
}

struct AnalysisSnapshotBuilder {
    let calendar: Calendar
    private let referenceMileageKm = 40.0

    func build(days: [RunningLoadDay], loads: TrainingLoadResult) -> AnalysisSnapshot {
        let sorted = days.sorted { $0.date < $1.date }
        let weeklyVolumes = buildWeeklyVolumes(days: sorted)
        let sevenDayDistance = sorted.suffix(7).map(\.runningDistanceKm).reduce(0, +)
        let totalDistance = sorted.map(\.runningDistanceKm).reduce(0, +)
        let variation = weeklyVariation(from: weeklyVolumes)
        let lastRunDate = sorted.last(where: { $0.runningDistanceKm > 0 })?.date
        let daysSinceLastRun = lastRunDate.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: Date())).day ?? 0 }

        let snapshot = AnalysisSnapshot(
            generatedAt: Date(),
            weeklyVolumes: weeklyVolumes,
            shortTermLoad: loads.shortTerm,
            longTermLoad: loads.longTerm,
            loadBalance: loads.balance,
            sevenDayDistanceKm: sevenDayDistance,
            fortyTwoDayDistanceKm: totalDistance,
            weeklyVariation: variation,
            daysSinceLastRun: daysSinceLastRun,
            insights: [],
            referenceMileageKm: referenceMileageKm
        )

        return AnalysisSnapshot(
            generatedAt: snapshot.generatedAt,
            weeklyVolumes: snapshot.weeklyVolumes,
            shortTermLoad: snapshot.shortTermLoad,
            longTermLoad: snapshot.longTermLoad,
            loadBalance: snapshot.loadBalance,
            sevenDayDistanceKm: snapshot.sevenDayDistanceKm,
            fortyTwoDayDistanceKm: snapshot.fortyTwoDayDistanceKm,
            weeklyVariation: snapshot.weeklyVariation,
            daysSinceLastRun: snapshot.daysSinceLastRun,
            insights: buildInsights(snapshot),
            referenceMileageKm: snapshot.referenceMileageKm
        )
    }

    private func buildWeeklyVolumes(days: [RunningLoadDay]) -> [AnalysisWeekVolume] {
        let grouped = Dictionary(grouping: days) { mondayStart(for: $0.date) }
        let starts = grouped.keys.sorted()
        let currentWeek = mondayStart(for: Date())

        return starts.map { start in
            let distance = grouped[start, default: []].map(\.runningDistanceKm).reduce(0, +)
            let label = weekLabel(start)
            return AnalysisWeekVolume(
                startDate: start,
                label: label,
                distanceKm: distance,
                isCurrent: calendar.isDate(start, inSameDayAs: currentWeek)
            )
        }
    }

    private func buildInsights(_ snapshot: AnalysisSnapshot) -> [AnalysisInsight] {
        [
            volumeInsight(snapshot),
            loadInsight(snapshot),
            stabilityInsight(snapshot),
            consistencyInsight(snapshot),
            intensityInsight()
        ]
    }

    private func volumeInsight(_ snapshot: AnalysisSnapshot) -> AnalysisInsight {
        let current = snapshot.weeklyVolumes.last?.distanceKm ?? 0

        if current >= referenceMileageKm {
            return AnalysisInsight(
                title: "训练量：基础跑量达标",
                message: "知识库建议先靠稳定跑量打有氧地基。当前周跑量已接近业余 5K 基础区间下沿，可以继续用轻松跑维持。", 
                icon: "chart.bar.fill",
                tint: AppColor.success
            )
        }

        return AnalysisInsight(
            title: "训练量：优先建立地基",
            message: "知识库把跑量视为长期表现的最大差异因素。当前周跑量低于 40 km 参考线，建议先稳定增加轻松跑，不急着堆强度。",
            icon: "chart.bar",
            tint: AppColor.warning
        )
    }

    private func loadInsight(_ snapshot: AnalysisSnapshot) -> AnalysisInsight {
        AnalysisInsight(
            title: "负荷：\(snapshot.loadBalance.title)",
            message: "\(snapshot.loadBalance.guidance)。知识库原则是压力加恢复才会成长，短期负荷高于长期负荷太多时，下一跑应偏轻松。",
            icon: "waveform.path.ecg",
            tint: snapshot.statusTint
        )
    }

    private func stabilityInsight(_ snapshot: AnalysisSnapshot) -> AnalysisInsight {
        guard let variation = snapshot.weeklyVariation else {
            return AnalysisInsight(
                title: "稳定性：等待更多数据",
                message: "需要至少几周跑量才能判断波动。知识库强调持续出现，比偶尔一周猛练更重要。",
                icon: "point.3.connected.trianglepath.dotted",
                tint: AppColor.textTertiary
            )
        }

        if variation > 0.4 {
            return AnalysisInsight(
                title: "稳定性：周跑量波动偏大",
                message: "最近周跑量变异超过 40%。建议把增量拆到多天轻松跑，避免一周猛增后一周中断。",
                icon: "point.3.connected.trianglepath.dotted",
                tint: AppColor.warning
            )
        }

        return AnalysisInsight(
            title: "稳定性：节奏不错",
            message: "周跑量波动处在可控范围。继续保持难易交替，每周质量课不要连续堆在一起。",
            icon: "checkmark.seal",
            tint: AppColor.success
        )
    }

    private func consistencyInsight(_ snapshot: AnalysisSnapshot) -> AnalysisInsight {
        guard let days = snapshot.daysSinceLastRun else {
            return AnalysisInsight(
                title: "连续性：暂无跑步记录",
                message: "先从 20-30 分钟轻松跑开始，建立可持续习惯。",
                icon: "figure.run",
                tint: AppColor.textTertiary
            )
        }

        if days > 2 {
            return AnalysisInsight(
                title: "连续性：先打破停跑循环",
                message: "距上次跑步已超过 2 天。今天优先安排低强度短跑，不追配速，先恢复训练节奏。",
                icon: "figure.run.square.stack",
                tint: AppColor.warning
            )
        }

        return AnalysisInsight(
            title: "连续性：训练节奏在线",
            message: "最近仍有跑步记录。若身体轻松，可以正常进入下一次计划；若疲劳明显，就保留轻松跑。",
            icon: "figure.run.circle",
            tint: AppColor.success
        )
    }

    private func intensityInsight() -> AnalysisInsight {
        AnalysisInsight(
            title: "80/20：等待心率分区",
            message: "知识库建议大约 80% 轻松、20% 较难。当前首版只读取跑步距离和运动时间；接入心率分区后会显示低强度与硬课比例。",
            icon: "slider.horizontal.3",
            tint: AppColor.accent
        )
    }

    private func weeklyVariation(from weeks: [AnalysisWeekVolume]) -> Double? {
        let values = weeks.filter { !$0.isCurrent && $0.distanceKm > 0 }.map(\.distanceKm)
        guard values.count >= 3 else { return nil }

        let mean = values.reduce(0, +) / Double(values.count)
        guard mean > 0 else { return nil }

        let variance = values.reduce(0) { total, value in
            total + pow(value - mean, 2)
        } / Double(values.count)

        return sqrt(variance) / mean
    }

    private func mondayStart(for date: Date) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: dayStart)
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: dayStart) ?? dayStart
    }

    private func weekLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}
