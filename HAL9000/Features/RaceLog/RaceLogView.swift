import SwiftUI

struct RaceLogView: View {
    @StateObject private var viewModel = RaceLogViewModel()
    @AppStorage("intervalsAthleteId") private var intervalsAthleteId = ""
    @State private var intervalsApiKey = ""
    @State private var showingSettings = false

    private let intervalsApiKeyStorageKey = "intervalsApiKey"

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header

                        switch viewModel.state {
                        case .idle:
                            setupContent
                        case .loading:
                            loadingContent
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
                    await loadRaces()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) {
                intervalsSettings
            }
            .task {
                loadIntervalsCredentials()
                await loadRaces()
            }
        }
        .supportsSwipeBack()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Race Log")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.pageTitle)
                Text("Intervals.icu 比赛地图")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "key")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColor.accent)
                        .frame(width: 42, height: 42)
                        .background(AppColor.controlBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    Task { await loadRaces() }
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
    }

    private func loadedContent(_ snapshot: RaceLogSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            mapCard(snapshot)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricCard("比赛", "\(snapshot.races.count)", "已识别", "flag.checkered", AppColor.accent)
                metricCard("有地图", "\(snapshot.mappedRaces.count)", "可标记", "map", AppColor.success)
                metricCard("总距离", snapshot.totalDistanceText, "比赛累计", "ruler", AppColor.warning)
                metricCard("最快", snapshot.fastestPaceText, "平均配速", "speedometer", AppColor.success)
            }

            sectionHeader("比赛记录")

            if snapshot.races.isEmpty {
                raceCard {
                    Text("没有识别到比赛")
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("我会从活动名称和标签里识别 race、marathon、5K、10K、半马、全马、比赛等关键词；PB 只计算 10K、半马和全马。")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
            } else {
                ForEach(snapshot.races) { race in
                    NavigationLink {
                        RaceDetailView(
                            race: race,
                            apiKey: intervalsApiKey,
                            isPB: snapshot.pbRaceIds.contains(race.id)
                        )
                    } label: {
                        raceRow(race, isPB: snapshot.pbRaceIds.contains(race.id))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func mapCard(_ snapshot: RaceLogSnapshot) -> some View {
        raceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("比赛地图")
                        .font(AppTypography.title3)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text("\(snapshot.mappedRaces.count) 个坐标")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                RaceMapView(races: snapshot.mappedRaces)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                Text(snapshot.mapNote)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var setupContent: some View {
        raceCard {
            VStack(spacing: 14) {
                Image(systemName: "key.radiowaves.forward")
                    .font(.system(size: 34))
                    .foregroundStyle(AppColor.accent)
                Text("连接 Intervals.icu")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text("输入 Intervals.icu API Key 后，我会拉取跑步活动，自动识别比赛并把有坐标的比赛标在地图上。")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                PrimaryButton("填写 API Key") {
                    showingSettings = true
                }
            }
        }
    }

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 18)
                .fill(AppColor.controlBackground)
                .frame(height: 360)

            HStack(spacing: 10) {
                ForEach(0..<2) { _ in
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppColor.cardBackground)
                        .frame(height: 110)
                }
            }

            ForEach(0..<3) { _ in
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppColor.cardBackground)
                    .frame(height: 96)
            }
        }
    }

    private func errorContent(_ message: String) -> some View {
        raceCard {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 34))
                    .foregroundStyle(AppColor.warning)
                Text("Intervals.icu 读取失败")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(message)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    PrimaryButton("检查 Key") {
                        showingSettings = true
                    }
                    PrimaryButton("重试") {
                        Task { await loadRaces() }
                    }
                }
            }
        }
    }

    private var intervalsSettings: some View {
        NavigationStack {
            Form {
                Section("Intervals.icu API") {
                    SecureField("API Key", text: $intervalsApiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Athlete ID，可留空自动读取", text: $intervalsAthleteId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    Text("认证方式：Basic Auth，用户名固定为 API_KEY，密码为 Intervals.icu settings 页面生成的 API Key。Athlete ID 形如 i 加数字。")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            .navigationTitle("Race Log 设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        showingSettings = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存并刷新") {
                        saveIntervalsCredentials()
                        showingSettings = false
                        Task { await loadRaces() }
                    }
                }
            }
        }
        .supportsSwipeBack()
    }

    private func raceRow(_ race: RaceActivity, isPB: Bool) -> some View {
        raceCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: race.coordinate == nil ? "flag" : "mappin.and.ellipse")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(race.coordinate == nil ? AppColor.warning : AppColor.success)
                    .frame(width: 42, height: 42)
                    .background((race.coordinate == nil ? AppColor.warning : AppColor.success).opacity(0.13))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(race.name)
                            .font(AppTypography.headline)
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        if isPB {
                            Label("PB", systemImage: "trophy.fill")
                                .font(AppTypography.captionBold)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.14))
                                .clipShape(Capsule())
                        } else {
                            Text(race.dateText)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }

                    raceMetricStrip(race)

                    if let location = race.locationText {
                        Label(location, systemImage: "location")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    if isPB {
                        Text(race.dateText)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .padding(.top, 13)
            }
        }
    }

    private func raceMetricStrip(_ race: RaceActivity) -> some View {
        HStack(spacing: 10) {
            compactMetric(race.distanceText, icon: "ruler")
            compactMetric(race.durationText, icon: "stopwatch")
            compactMetric(race.paceText, icon: "speedometer")
            if race.category != .other {
                compactMetric(race.category.displayName, icon: "flag.checkered")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactMetric(_ text: String, icon: String) -> some View {
        Label {
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        } icon: {
            Image(systemName: icon)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(AppColor.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func metricCard(_ title: String, _ value: String, _ subtitle: String, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textPrimary)
            Text(subtitle)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.contentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.title3)
            .foregroundStyle(AppColor.pageTitle)
            .padding(.top, 2)
    }

    private func raceCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.contentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 8)
    }

    private func loadRaces() async {
        let apiKey = intervalsApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let athleteId = intervalsAthleteId.trimmingCharacters(in: .whitespacesAndNewlines)
        await viewModel.load(apiKey: apiKey, athleteId: athleteId)

        if case .loaded(let snapshot) = viewModel.state,
           intervalsAthleteId.isEmpty,
           let resolvedId = snapshot.athleteId {
            intervalsAthleteId = resolvedId
        }
    }

    private func loadIntervalsCredentials() {
        intervalsApiKey = KeychainStore.string(for: intervalsApiKeyStorageKey)
    }

    private func saveIntervalsCredentials() {
        let trimmedApiKey = intervalsApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        intervalsApiKey = trimmedApiKey
        KeychainStore.set(trimmedApiKey, for: intervalsApiKeyStorageKey)
    }
}
