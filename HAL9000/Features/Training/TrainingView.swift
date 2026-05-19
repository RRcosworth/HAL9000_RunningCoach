import SwiftUI
import UIKit

struct TrainingView: View {
    @StateObject private var viewModel = TrainingViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header

                        switch viewModel.state {
                        case .idle, .loading:
                            skeletonContent
                        case .loaded:
                            loadedContent
                        case .empty:
                            emptyContent
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
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await viewModel.load()
            }
        }
        .supportsSwipeBack()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Training")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.pageTitle)

                Text(weekRangeText)
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

    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let progress = viewModel.progress {
                progressCard(progress)
            }

            if let summary = viewModel.summary {
                weeklyStatsRow(summary: summary)
            }

            exportSection
            planSection
            historySection
        }
    }

    private var exportSection: some View {
        trainingCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("导出课表")
                            .font(AppTypography.title3)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(viewModel.exportState.message)
                            .font(AppTypography.footnote)
                            .foregroundStyle(exportMessageColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "applewatch")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppColor.accent)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await viewModel.exportToAppleWatch() }
                    } label: {
                        exportButtonLabel("Apple Watch", icon: "applewatch")
                    }
                    .buttonStyle(.plain)

                    if let url = viewModel.garminExportURL {
                        ShareLink(item: url) {
                            exportButtonLabel("分享 TCX", icon: "square.and.arrow.up")
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            viewModel.prepareGarminExport()
                        } label: {
                            exportButtonLabel("Garmin", icon: "location.north.line")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("动态训练计划", trailing: "\(plannedSessions.count) 项")

            if plannedSessions.isEmpty {
                trainingCard {
                    Label("本周计划已完成", systemImage: "checkmark.seal.fill")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColor.success)
                    Text("后续以恢复、拉伸和睡眠为主，等待 Hermes 生成下一周安排。")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
            } else {
                ForEach(plannedSessions) { session in
                    planCard(session)
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("训练历史", trailing: "\(completedSessions.count) 次")

            if completedSessions.isEmpty {
                trainingCard {
                    Text("暂无已完成训练")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("完成一次跑步后，这里会按时间显示距离、时长和心率。")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
            } else {
                ForEach(completedSessions) { session in
                    if let workout = session.workoutSummary {
                        NavigationLink {
                            TodayWorkoutDetailView(workout: workout)
                        } label: {
                            historyCard(session, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        historyCard(session, showsChevron: false)
                    }
                }
            }
        }
    }

    private func progressCard(_ progress: TrainingProgress) -> some View {
        trainingCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本周进度")
                            .font(AppTypography.title3)
                            .foregroundStyle(AppColor.textPrimary)
                        Text(progress.guidance)
                            .font(AppTypography.footnote)
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text(progress.percentText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.accent)
                }

                ProgressView(value: progress.completionRatio)
                    .tint(AppColor.accent)
                    .scaleEffect(x: 1, y: 1.5, anchor: .center)

                HStack(spacing: 10) {
                    metricPill(title: "已完成", value: progress.completedDistanceKm)
                    metricPill(title: "目标", value: progress.targetDistanceKm)
                    metricPill(title: "剩余", value: progress.remainingDistanceKm)
                }
            }
        }
    }

    private func weeklyStatsRow(summary: WeeklySummary) -> some View {
        HStack(spacing: 10) {
            statCard(icon: "figure.run", value: summary.totalDistanceKm, label: "距离")
            statCard(icon: "clock", value: summary.totalDurationFormatted, label: "时长")
            statCard(icon: "checklist", value: "\(summary.totalActivities)", label: "次数")
        }
    }

    private func planCard(_ session: TrainingSession) -> some View {
        trainingCard {
            HStack(alignment: .top, spacing: 12) {
                statusIcon(session, tint: AppColor.accent)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(session.name)
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text(dayText(session.date))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    Text(session.description ?? "按当前周进度自动安排，优先保证轻松完成。")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        infoChip(session.planDistanceKm, icon: "ruler")
                        infoChip(session.durationFormatted, icon: "stopwatch")
                        if let zone = session.zone, !zone.isEmpty {
                            infoChip(zone, icon: "waveform.path.ecg")
                        }
                    }
                }
            }
        }
    }

    private func historyCard(_ session: TrainingSession, showsChevron: Bool) -> some View {
        trainingCard {
            HStack(spacing: 12) {
                statusIcon(session, tint: AppColor.success)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(session.name)
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(dayText(session.date))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    HStack(spacing: 10) {
                        Label(session.distanceKm, systemImage: "ruler")
                        Label(session.durationFormatted, systemImage: "stopwatch")
                        if let hr = session.heartRateFormatted {
                            Label(hr, systemImage: "heart")
                        }
                    }
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                }

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
        }
    }

    private var skeletonContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColor.controlBackground)
                .frame(width: 180, height: 26)

            ForEach(0..<4) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppColor.cardBackground)
                    .frame(height: 112)
            }
        }
    }

    private var emptyContent: some View {
        trainingCard {
            EmptyStateView(
                systemImage: "figure.run",
                title: "本周暂无训练数据",
                subtitle: "完成一次训练后，Hermes 会根据每周进度生成下一步安排。",
                actionTitle: "刷新",
                action: { Task { await viewModel.refresh() } }
            )
        }
    }

    private func errorContent(_ message: String) -> some View {
        trainingCard {
            VStack(spacing: 14) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 34))
                    .foregroundStyle(AppColor.error)
                Text("加载失败")
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

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .font(AppTypography.title3)
                .foregroundStyle(AppColor.pageTitle)
            Spacer()
            Text(trailing)
                .font(AppTypography.subheadline)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.top, 2)
    }

    private func trainingCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.contentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 8)
    }

    private func statCard(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColor.accent)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppColor.contentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func infoChip(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(AppTypography.caption)
            .foregroundStyle(AppColor.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(AppColor.cardBackground)
            .clipShape(Capsule())
    }

    private func exportButtonLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(AppColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statusIcon(_ session: TrainingSession, tint: Color) -> some View {
        Image(systemName: session.isCompleted ? "checkmark.circle.fill" : session.typeIcon)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 42, height: 42)
            .background(tint.opacity(0.12))
            .clipShape(Circle())
    }

    private var plannedSessions: [TrainingSession] {
        viewModel.sessions.filter { !$0.isCompleted }
    }

    private var completedSessions: [TrainingSession] {
        viewModel.sessions.filter(\.isCompleted)
    }

    private var exportMessageColor: Color {
        switch viewModel.exportState {
        case .failed:
            return AppColor.error
        case .succeeded:
            return AppColor.success
        default:
            return AppColor.textSecondary
        }
    }

    private var weekRangeText: String {
        guard let summary = viewModel.summary, !summary.weekStart.isEmpty else {
            return "本周训练计划与历史"
        }
        return formatWeekRange(summary.weekStart)
    }

    private func formatWeekRange(_ startDate: String) -> String {
        let isoRange = startDate.split(separator: " ").first.map(String.init) ?? startDate
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        guard let start = fmt.date(from: isoRange) else {
            return startDate
        }

        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let out = DateFormatter()
        out.dateFormat = "M/d"
        return "\(out.string(from: start)) - \(out.string(from: end))"
    }

    private func dayText(_ date: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let value = fmt.date(from: date) else { return date }

        let out = DateFormatter()
        out.locale = Locale(identifier: "zh_CN")
        out.dateFormat = "E M/d"
        return out.string(from: value)
    }
}
