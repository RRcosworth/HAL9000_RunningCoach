import SwiftUI
import UIKit

struct TrainingView: View {
    @StateObject private var viewModel = TrainingViewModel()
    @State private var showsExportSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                GeometryReader { geometry in
                    ScrollView(.vertical, showsIndicators: true) {
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
                        .frame(width: geometry.size.width, alignment: .topLeading)
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .vertical)
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
            if let cacheNotice = viewModel.cacheNotice {
                cacheNoticeCard(cacheNotice)
            }

            if let progress = viewModel.progress {
                progressCard(progress)
            }

            if let summary = viewModel.summary {
                weeklyStatsRow(summary: summary)
            }

            exportSection
            weekPlanSection
            historySection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showsExportSheet) {
            exportSheet
        }
    }

    private var exportSection: some View {
        trainingCard {
            Button {
                viewModel.selectAllExportableSessions()
                showsExportSheet = true
            } label: {
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
            }
            .buttonStyle(.plain)
        }
    }

    private var weekPlanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("本周训练计划", trailing: "\(viewModel.weekDays.count) 天")

            ForEach(viewModel.weekDays) { day in
                weekDayCard(day)
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

    private func cacheNoticeCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColor.warning)
            Text(message)
                .font(AppTypography.footnote)
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(AppColor.warning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func weekDayCard(_ day: TrainingWeekDay) -> some View {
        trainingCard {
            let primarySession = day.primarySession

            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 3) {
                    Text(day.weekday)
                        .font(AppTypography.captionBold)
                    Text(day.title)
                        .font(AppTypography.caption)
                }
                .foregroundStyle(day.isToday ? AppColor.accent : AppColor.textSecondary)
                .frame(width: 48)
                .padding(.vertical, 7)
                .background(day.isToday ? AppColor.accent.opacity(0.12) : AppColor.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Image(systemName: primarySession?.typeIcon ?? "moon.zzz.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(day.isRestDay ? AppColor.textTertiary : AppColor.accent)
                    .frame(width: 38, height: 38)
                    .background((day.isRestDay ? AppColor.textTertiary : AppColor.accent).opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(dayTitle(day))
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        if !day.isRestDay {
                            Text(day.sessions.allSatisfy(\.isCompleted) ? "已完成" : "未完成")
                                .font(AppTypography.caption)
                                .foregroundStyle(day.sessions.allSatisfy(\.isCompleted) ? AppColor.success : AppColor.warning)
                        }
                    }

                    Text(day.recoveryAdvice)
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !day.sessions.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(day.sessions) { session in
                                weekSessionRow(session)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func dayTitle(_ day: TrainingWeekDay) -> String {
        if day.sessions.isEmpty {
            return "休息日"
        }

        if day.sessions.count == 1 {
            return day.sessions[0].name
        }

        return "\(day.sessions.count) 项训练"
    }

    private func weekSessionRow(_ session: TrainingSession) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.name)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(session.isCompleted ? "已完成" : "未完成")
                    .font(AppTypography.caption)
                    .foregroundStyle(session.isCompleted ? AppColor.success : AppColor.warning)
            }

            HStack(spacing: 8) {
                infoChip(session.planDistanceKm, icon: "ruler")
                infoChip(session.durationFormatted, icon: "stopwatch")
                if let zone = session.zone, !zone.isEmpty {
                    infoChip(zone, icon: "waveform.path.ecg")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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
        viewModel.sessions
            .filter(\.isCompleted)
            .filter { (($0.actualDistance ?? $0.distance) > 0) || (($0.actualDuration ?? $0.duration) > 0) }
            .sorted {
                ($0.startedAt ?? $0.exportDate) > ($1.startedAt ?? $1.exportDate)
            }
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

    private var exportSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.exportableSessions.isEmpty {
                    EmptyStateView(
                        systemImage: "applewatch",
                        title: "没有可导出的训练",
                        subtitle: "只有未完成的跑步计划会出现在这里。",
                        actionTitle: nil,
                        action: nil
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(viewModel.exportableSessions) { session in
                                exportSelectionRow(session)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    VStack(spacing: 10) {
                        Button {
                            Task { await viewModel.exportToAppleWatch(viewModel.selectedExportSessions) }
                        } label: {
                            exportButtonLabel("同步到 Apple Watch", icon: "applewatch")
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.selectedExportSessions.isEmpty)
                        .opacity(viewModel.selectedExportSessions.isEmpty ? 0.5 : 1)

                        if let url = viewModel.garminExportURL {
                            ShareLink(item: url) {
                                exportButtonLabel("分享 Garmin TCX", icon: "square.and.arrow.up")
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                viewModel.prepareGarminExport(viewModel.selectedExportSessions)
                            } label: {
                                exportButtonLabel("生成 Garmin TCX", icon: "location.north.line")
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.selectedExportSessions.isEmpty)
                            .opacity(viewModel.selectedExportSessions.isEmpty ? 0.5 : 1)
                        }

                        Text(viewModel.exportState.message)
                            .font(AppTypography.footnote)
                            .foregroundStyle(exportMessageColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .background(AppBackground())
            .navigationTitle("选择导出训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { showsExportSheet = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.selectedExportSessions.count == viewModel.exportableSessions.count ? "清空" : "全选") {
                        if viewModel.selectedExportSessions.count == viewModel.exportableSessions.count {
                            viewModel.clearExportSelection()
                        } else {
                            viewModel.selectAllExportableSessions()
                        }
                    }
                    .disabled(viewModel.exportableSessions.isEmpty)
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func exportSelectionRow(_ session: TrainingSession) -> some View {
        Button {
            viewModel.toggleExportSelection(session)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: viewModel.selectedExportIDs.contains(session.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(viewModel.selectedExportIDs.contains(session.id) ? AppColor.accent : AppColor.textTertiary)

                VStack(alignment: .leading, spacing: 5) {
                    Text(session.name)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    Text("\(dayText(session.date)) · \(session.planDistanceKm) · \(session.durationFormatted)")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer()
            }
            .padding(14)
            .background(AppColor.contentBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
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
