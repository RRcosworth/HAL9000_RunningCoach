import SwiftUI

struct RaceDetailView: View {
    @StateObject private var viewModel: RaceDetailViewModel
    let apiKey: String
    let isPB: Bool

    init(race: RaceActivity, apiKey: String, isPB: Bool) {
        _viewModel = StateObject(wrappedValue: RaceDetailViewModel(race: race))
        self.apiKey = apiKey
        self.isPB = isPB
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    routeCard
                    titleCard
                    metricsGrid

                    if !viewModel.splits.isEmpty {
                        splitsCard
                    }

                    Color.clear.frame(height: 88)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
        .navigationTitle("Race Detail")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load(apiKey: apiKey)
        }
        .supportsSwipeBack()
    }

    private var routeCard: some View {
        detailCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("轨迹地图")
                        .font(AppTypography.title3)
                        .foregroundStyle(AppColor.textPrimary)
                    Spacer()
                    Text(routeStatusText)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }

                ZStack {
                    RouteMapView(coordinates: viewModel.coordinates)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    if case .loading = viewModel.state, viewModel.coordinates.isEmpty {
                        ProgressView()
                            .padding(14)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    } else if viewModel.coordinates.isEmpty {
                        Text("无 GPS 轨迹数据")
                            .font(AppTypography.footnote)
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                }

                if case .partial(let message) = viewModel.state {
                    Text(message)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColor.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var titleCard: some View {
        detailCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(viewModel.race.name)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(2)

                    Spacer()

                    if isPB {
                        pbBadge
                    }
                }

                HStack(spacing: 8) {
                    infoChip(viewModel.race.dateText, icon: "calendar")
                    infoChip(viewModel.race.category.displayName, icon: "flag.checkered")
                }

                if let location = viewModel.race.locationText {
                    Label(location, systemImage: "location")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metricTile("距离", viewModel.race.distanceText, "ruler")
            metricTile("时间", viewModel.race.detailDurationText, "stopwatch")
            metricTile("配速", viewModel.race.paceText, "speedometer")
            metricTile("平均心率", heartRateText, "heart.fill")
            metricTile("爬升", elevationText, "mountain.2.fill")
            metricTile("步频", cadenceText, "metronome")
            metricTile("卡路里", caloriesText, "flame.fill")
            metricTile("最大心率", maxHeartRateText, "waveform.path.ecg")
        }
    }

    private var splitsCard: some View {
        detailCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("配速分析")
                    .font(AppTypography.title3)
                    .foregroundStyle(AppColor.textPrimary)

                ForEach(viewModel.splits) { split in
                    HStack(alignment: .firstTextBaseline) {
                        Text(split.titleText)
                            .font(AppTypography.subheadline)
                            .foregroundStyle(AppColor.textPrimary)
                        Spacer()
                        Text(split.durationText)
                            .font(AppTypography.footnote)
                            .foregroundStyle(AppColor.textSecondary)
                        Text(split.paceText)
                            .font(AppTypography.footnote)
                            .foregroundStyle(AppColor.accent)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var pbBadge: some View {
        Label("PB", systemImage: "trophy.fill")
            .font(AppTypography.captionBold)
            .foregroundStyle(.orange)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.orange.opacity(0.14))
            .clipShape(Capsule())
    }

    private func metricTile(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColor.accent)
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textSecondary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.textPrimary)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.contentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 7)
    }

    private func detailCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.contentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 8)
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

    private var routeStatusText: String {
        if viewModel.coordinates.isEmpty {
            return "等待轨迹"
        }

        return "\(viewModel.coordinates.count) 个定位点"
    }

    private var heartRateText: String {
        viewModel.race.averageHeartRate.map { "\($0) bpm" } ?? "--"
    }

    private var maxHeartRateText: String {
        viewModel.race.maxHeartRate.map { "\($0) bpm" } ?? "--"
    }

    private var elevationText: String {
        viewModel.race.totalElevationGain.map { String(format: "%.0f m", $0) } ?? "--"
    }

    private var cadenceText: String {
        viewModel.race.averageCadence.map { String(format: "%.0f spm", $0) } ?? "--"
    }

    private var caloriesText: String {
        viewModel.race.calories.map { "\($0) kcal" } ?? "--"
    }
}

private extension RaceActivity {
    var detailDurationText: String {
        let hours = movingTimeSeconds / 3600
        let minutes = (movingTimeSeconds % 3600) / 60
        let seconds = movingTimeSeconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
    }
}
