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

            intensityCard(snapshot)
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

    private func intensityCard(_ snapshot: AnalysisSnapshot) -> some View {
        analysisCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("80/20 强度分布")
                        .font(AppTypography.title3)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text("42 天")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                if let intensity = snapshot.intensity, intensity.hasEnoughData {
                    HStack(spacing: 10) {
                        ratioPill("轻松 Z1-Z2", intensity.easyText, AppColor.success)
                        ratioPill("较难 Z3-Z5", intensity.hardText, AppColor.warning)
                    }

                    VStack(spacing: 8) {
                        ForEach(intensity.zones) { zone in
                            zoneRow(zone)
                        }
                    }

                    Text("按跑步 workout 内心率样本计算。知识库口径：大多数训练应落在轻松区，质量课作为少量高刺激。")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.text.square")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(AppColor.textTertiary)
                            .frame(width: 42, height: 42)
                            .background(AppColor.cardBackground)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text("等待跑步心率样本")
                                .font(AppTypography.headline)
                                .foregroundStyle(AppColor.textPrimary)
                            Text("佩戴手表跑步后，这里会显示 Z1-Z5 和 80/20 比例。")
                                .font(AppTypography.footnote)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                }
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

    private func ratioPill(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func zoneRow(_ zone: HRZoneBreakdown) -> some View {
        HStack(spacing: 10) {
            Text("Z\(zone.zone)")
                .font(AppTypography.captionBold)
                .foregroundStyle(zoneColor(zone.zone))
                .frame(width: 28, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColor.cardBackground)
                    Capsule()
                        .fill(zoneColor(zone.zone))
                        .frame(width: max(4, geometry.size.width * zone.percentage / 100))
                }
            }
            .frame(height: 8)

            Text(String(format: "%.0f%%", zone.percentage))
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func zoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: return AppColor.accent
        case 2: return AppColor.success
        case 3: return AppColor.warning
        case 4: return Color.orange
        default: return AppColor.error
        }
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
            async let daysResult = healthService.fetchRunningLoadDays(days: 180)
            async let heartRateSamplesResult = fetchOptionalRunningHeartRateSamples()
            async let maxHeartRateResult = fetchOptionalMaxHeartRate()

            let days = try await daysResult
            let heartRateSamples = await heartRateSamplesResult
            let maxHeartRate = await maxHeartRateResult
            let tsbResult = loadCalculator.calculateTSB(days: days)
            let hasEnoughTSBData = days.filter { $0.runningDistanceKm > 0 || $0.exerciseMinutes > 0 }.count >= 42
            let snapshot = AnalysisSnapshotBuilder(calendar: calendar).build(
                days: days,
                tsbResult: tsbResult,
                hasEnoughTSBData: hasEnoughTSBData,
                heartRateSamples: heartRateSamples,
                maxHeartRate: maxHeartRate
            )
            state = .loaded(snapshot)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func fetchOptionalRunningHeartRateSamples() async -> [HeartRateSample] {
        do {
            return try await healthService.fetchRunningHeartRateSamples(days: 42)
        } catch {
            return []
        }
    }

    private func fetchOptionalMaxHeartRate() async -> Double {
        do {
            return try await healthService.fetchMaxHeartRate()
        } catch {
            return 190
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
    let tsbValue: Double?
    let sevenDayDistanceKm: Double
    let fortyTwoDayDistanceKm: Double
    let weeklyVariation: Double?
    let daysSinceLastRun: Int?
    let intensity: IntensityBalance?
    let insights: [AnalysisInsight]
    let referenceMileageKm: Double

    func withInsights(_ insights: [AnalysisInsight]) -> AnalysisSnapshot {
        AnalysisSnapshot(
            generatedAt: generatedAt,
            weeklyVolumes: weeklyVolumes,
            shortTermLoad: shortTermLoad,
            longTermLoad: longTermLoad,
            loadBalance: loadBalance,
            tsbValue: tsbValue,
            sevenDayDistanceKm: sevenDayDistanceKm,
            fortyTwoDayDistanceKm: fortyTwoDayDistanceKm,
            weeklyVariation: weeklyVariation,
            daysSinceLastRun: daysSinceLastRun,
            intensity: intensity,
            insights: insights,
            referenceMileageKm: referenceMileageKm
        )
    }

    var sevenDayDistanceText: String {
        String(format: "%.1f km", sevenDayDistanceKm)
    }

    var fortyTwoDayDistanceText: String {
        String(format: "%.0f km", fortyTwoDayDistanceKm)
    }

    var tsb: Double? {
        tsbValue
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

struct IntensityBalance: Equatable {
    let easyPercent: Double
    let hardPercent: Double
    let totalSamples: Int
    let maxHeartRate: Double
    let zones: [HRZoneBreakdown]

    var easyText: String {
        String(format: "%.0f%%", easyPercent)
    }

    var hardText: String {
        String(format: "%.0f%%", hardPercent)
    }

    var isAlignedWith8020: Bool {
        (75...90).contains(easyPercent)
    }

    var hasEnoughData: Bool {
        totalSamples >= 20
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

    func build(
        days: [RunningLoadDay],
        tsbResult: TSBResult,
        hasEnoughTSBData: Bool,
        heartRateSamples: [HeartRateSample] = [],
        maxHeartRate: Double = 190
    ) -> AnalysisSnapshot {
        let sorted = days.sorted { $0.date < $1.date }
        let analysisDays = Array(sorted.suffix(42))
        let weeklyVolumes = buildWeeklyVolumes(days: analysisDays)
        let sevenDayDistance = analysisDays.suffix(7).map(\.runningDistanceKm).reduce(0, +)
        let totalDistance = analysisDays.map(\.runningDistanceKm).reduce(0, +)
        let variation = weeklyVariation(from: weeklyVolumes)
        let lastRunDate = analysisDays.last(where: { $0.runningDistanceKm > 0 })?.date
        let daysSinceLastRun = lastRunDate.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: Date())).day ?? 0 }
        let tsbState = TSBCalculator().state(for: tsbResult.current.tsb, hasEnoughData: hasEnoughTSBData)
        let loadBalance = loadBalance(for: tsbState)
        let intensity = buildIntensityBalance(samples: heartRateSamples, maxHeartRate: maxHeartRate)

        let snapshot = AnalysisSnapshot(
            generatedAt: Date(),
            weeklyVolumes: weeklyVolumes,
            shortTermLoad: TrainingLoadMetric(
                value: hasEnoughTSBData ? tsbResult.current.atl : nil,
                label: "ATL",
                trend: .unknown,
                subtitle: "7天 EWMA"
            ),
            longTermLoad: TrainingLoadMetric(
                value: hasEnoughTSBData ? tsbResult.current.ctl : nil,
                label: "CTL",
                trend: .unknown,
                subtitle: "42天 EWMA"
            ),
            loadBalance: loadBalance,
            tsbValue: hasEnoughTSBData ? tsbResult.current.tsb : nil,
            sevenDayDistanceKm: sevenDayDistance,
            fortyTwoDayDistanceKm: totalDistance,
            weeklyVariation: variation,
            daysSinceLastRun: daysSinceLastRun,
            intensity: intensity,
            insights: [],
            referenceMileageKm: referenceMileageKm
        )

        return snapshot.withInsights(buildInsights(snapshot))
    }

    private func loadBalance(for tsbState: TSBState) -> LoadBalanceState {
        switch tsbState {
        case .fresh:
            return .fresh
        case .neutral:
            return .productive
        case .fatigued, .highRisk:
            return .strained
        case .noData:
            return .unknown
        }
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
            intensityInsight(snapshot)
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

    private func intensityInsight(_ snapshot: AnalysisSnapshot) -> AnalysisInsight {
        guard let intensity = snapshot.intensity, intensity.hasEnoughData else {
            return AnalysisInsight(
                title: "80/20：等待跑步心率",
                message: "知识库建议大约 80% 轻松、20% 较难。当前没有足够的跑步 workout 心率样本；佩戴手表完成几次跑步后会显示真实比例。",
                icon: "slider.horizontal.3",
                tint: AppColor.textTertiary
            )
        }

        if intensity.isAlignedWith8020 {
            return AnalysisInsight(
                title: "80/20：强度分配合理",
                message: "最近 42 天跑步心率显示低强度 \(intensity.easyText)，较高强度 \(intensity.hardText)。这接近知识库建议的 80/20：多数跑轻松，少数训练拉开强度。",
                icon: "checkmark.seal",
                tint: AppColor.success
            )
        }

        if intensity.easyPercent < 75 {
            return AnalysisInsight(
                title: "80/20：轻松跑比例偏低",
                message: "最近 42 天低强度只有 \(intensity.easyText)，较高强度 \(intensity.hardText)。知识库提醒：中高强度堆太多会挤压恢复，建议把更多普通跑压回 Z1-Z2。",
                icon: "slider.horizontal.3",
                tint: AppColor.warning
            )
        }

        return AnalysisInsight(
            title: "80/20：轻松跑占比很高",
            message: "最近 42 天低强度达到 \(intensity.easyText)，较高强度 \(intensity.hardText)。这对恢复和基础期友好；若 TSB 稳定且身体状态好，可以保留少量节奏跑或间歇刺激。",
            icon: "slider.horizontal.3",
            tint: AppColor.accent
        )
    }

    private func buildIntensityBalance(samples: [HeartRateSample], maxHeartRate: Double) -> IntensityBalance? {
        guard !samples.isEmpty, maxHeartRate > 0 else { return nil }

        let calculator = HeartRateZoneCalculator()
        var counts = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]

        for sample in samples {
            let zone = calculator.classify(heartRate: sample.value, maxHR: maxHeartRate)
            counts[zone, default: 0] += 1
        }

        let total = counts.values.reduce(0, +)
        guard total > 0 else { return nil }

        let zones = (1...5).map { zone in
            let count = counts[zone, default: 0]
            return HRZoneBreakdown(
                zone: zone,
                name: calculator.zoneName(zone),
                rangeText: calculator.zoneRange(zone: zone, maxHR: maxHeartRate),
                minutes: Double(count),
                percentage: Double(count) / Double(total) * 100
            )
        }

        let easyPercent = Double((counts[1, default: 0] + counts[2, default: 0])) / Double(total) * 100
        return IntensityBalance(
            easyPercent: easyPercent,
            hardPercent: 100 - easyPercent,
            totalSamples: total,
            maxHeartRate: maxHeartRate,
            zones: zones
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
