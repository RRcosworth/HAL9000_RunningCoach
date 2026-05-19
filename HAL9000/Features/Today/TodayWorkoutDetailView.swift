import Charts
import MapKit
import SwiftUI

struct TodayWorkoutDetailView: View {
    let workout: TodayWorkoutSummary
    var healthService: HealthKitServing = HealthKitService.shared

    @Environment(\.dismiss) private var dismiss
    @State private var state: DetailState = .loading

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header

                switch state {
                case .loading:
                    loadingCard
                case .failed(let message):
                    errorCard(message)
                case .loaded(let detail):
                    detailContent(detail)
                }

                Color.clear.frame(height: 118)
            }
            .padding(.horizontal, 20)
            .padding(.top, 58)
        }
        .toolbar(.hidden, for: .navigationBar)
        .background { AppBackground() }
        .task { await load() }
        .supportsSwipeBack()
    }

    private var header: some View {
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
                Text(workout.title)
                    .font(AppTypography.title)
                    .foregroundStyle(AppColor.pageTitle)
                Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            Spacer()

            if case .loaded(let detail) = state {
                ShareLink(item: shareText(for: detail)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColor.accent)
                        .frame(width: 42, height: 42)
                        .background(AppColor.controlBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var loadingCard: some View {
        TodayCard {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(AppColor.accent)
                Text("正在读取运动详情")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 50)
        }
    }

    private func errorCard(_ message: String) -> some View {
        TodayCard {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppColor.warning)
                Text("读取详情失败")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.textPrimary)
                Text(message)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                PrimaryButton("重试") {
                    Task { await load() }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func detailContent(_ detail: WorkoutDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            routeCard(detail)
            metricsGrid(detail)
            heartRateCard(detail)
            splitsCard(detail)
        }
    }

    private func routeCard(_ detail: WorkoutDetail) -> some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader("轨迹地图", subtitle: detail.route.isEmpty ? "Apple 健康暂无路线" : "\(detail.route.count) 个定位点")
                WorkoutRouteMap(points: detail.route)
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func metricsGrid(_ detail: WorkoutDetail) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metricTile("距离", detail.distanceKm.map { String(format: "%.2f km", $0) } ?? "--", "ruler")
            metricTile("时长", durationText(detail.duration), "clock")
            metricTile("配速", detail.paceText, "speedometer")
            metricTile("能量", detail.activeEnergyKcal.map { String(format: "%.0f kcal", $0) } ?? "--", "flame.fill")
            metricTile("平均心率", detail.averageHeartRate.map { String(format: "%.0f bpm", $0) } ?? "--", "heart.fill")
            metricTile("最高心率", detail.maxHeartRate.map { String(format: "%.0f bpm", $0) } ?? "--", "heart.text.square.fill")
        }
    }

    private func heartRateCard(_ detail: WorkoutDetail) -> some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader("心率曲线", subtitle: detail.heartRateSamples.isEmpty ? "暂无心率样本" : "\(detail.heartRateSamples.count) 个样本")
                WorkoutChartOrEmpty(points: detail.heartRateSamples) {
                    Chart(detail.heartRateSamples, id: \.date) { sample in
                        LineMark(
                            x: .value("时间", sample.date),
                            y: .value("心率", sample.value)
                        )
                        .foregroundStyle(AppColor.warning)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private func splitsCard(_ detail: WorkoutDetail) -> some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader("公里分段", subtitle: detail.splits.isEmpty ? "路线不足，无法生成" : "\(detail.splits.count) 段")

                if detail.splits.isEmpty {
                    Text("Apple 健康没有提供足够路线点时，暂时无法计算每公里配速。")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(AppColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 10) {
                        ForEach(detail.splits) { split in
                            HStack {
                                Text("\(split.kilometer) km")
                                    .font(AppTypography.captionBold)
                                    .foregroundStyle(AppColor.textPrimary)
                                    .frame(width: 54, alignment: .leading)
                                Text(durationText(split.duration))
                                    .font(AppTypography.subheadline)
                                    .foregroundStyle(AppColor.textSecondary)
                                Spacer()
                                Text(split.averageHeartRate.map { String(format: "%.0f bpm", $0) } ?? "--")
                                    .font(AppTypography.subheadline)
                                    .foregroundStyle(AppColor.textPrimary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func metricTile(_ title: String, _ value: String, _ icon: String) -> some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                Text(title)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColor.textSecondary)
                Text(value)
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cardHeader(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(AppTypography.title3)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            Text(subtitle)
                .font(AppTypography.caption)
                .foregroundStyle(AppColor.textSecondary)
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await healthService.fetchWorkoutDetail(id: workout.id))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%dh%02dm", hours, minutes)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func shareText(for detail: WorkoutDetail) -> String {
        [
            "HAL9000 今日运动",
            "类型：\(detail.title)",
            "时间：\(detail.startedAt.formatted(date: .abbreviated, time: .shortened))",
            "距离：\(detail.distanceKm.map { String(format: "%.2f km", $0) } ?? "--")",
            "时长：\(durationText(detail.duration))",
            "配速：\(detail.paceText)",
            "平均心率：\(detail.averageHeartRate.map { String(format: "%.0f bpm", $0) } ?? "--")",
            "最高心率：\(detail.maxHeartRate.map { String(format: "%.0f bpm", $0) } ?? "--")"
        ].joined(separator: "\n")
    }

    private enum DetailState {
        case loading
        case loaded(WorkoutDetail)
        case failed(String)
    }
}

private struct WorkoutRouteMap: View {
    let points: [WorkoutRoutePoint]

    var body: some View {
        if coordinates.count >= 2 {
            Map(position: .constant(.region(region))) {
                MapPolyline(coordinates: coordinates)
                    .stroke(AppColor.accent, lineWidth: 4)
            }
            .mapControls {
                MapScaleView()
            }
        } else {
            ZStack {
                AppColor.controlBackground
                VStack(spacing: 10) {
                    Image(systemName: "map")
                        .font(.system(size: 30, weight: .semibold))
                    Text("暂无轨迹路线")
                        .font(AppTypography.subheadline)
                }
                .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private var coordinates: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var region: MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090), span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLat = latitudes.min() ?? first.latitude
        let maxLat = latitudes.max() ?? first.latitude
        let minLon = longitudes.min() ?? first.longitude
        let maxLon = longitudes.max() ?? first.longitude
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.35, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.35, 0.01)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

private struct WorkoutChartOrEmpty<Content: View, Data>: View {
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
                Text("暂无足够数据")
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
