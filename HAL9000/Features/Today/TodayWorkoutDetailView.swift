import Charts
import MapKit
import PhotosUI
import SwiftUI
import UIKit

struct TodayWorkoutDetailView: View {
    let workout: TodayWorkoutSummary
    var healthService: HealthKitServing = HealthKitService.shared

    @Environment(\.dismiss) private var dismiss
    @State private var state: DetailState = .loading
    @State private var shareDetail: WorkoutDetail?

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
        .fullScreenCover(item: $shareDetail) { detail in
            WorkoutShareSheet(detail: detail)
        }
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
                Button {
                    shareDetail = detail
                } label: {
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

private struct WorkoutShareSheet: View {
    let detail: WorkoutDetail

    @Environment(\.dismiss) private var dismiss
    @State private var mode: SharePosterMode = .photo
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var backgroundImage: UIImage?
    @State private var shareURL: URL?
    @State private var cityName = "运动地点"

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    poster
                        .frame(maxWidth: .infinity)
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 2))

                    modeControls
                    backgroundChoices
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
        }
        .background(Color(.systemGroupedBackground))
        .task {
            await resolveCityName()
            await renderShareImage()
        }
        .task(id: selectedPhoto) {
            await loadSelectedPhoto()
            await renderShareImage()
        }
        .onChange(of: mode) { _, _ in
            Task { await renderShareImage() }
        }
    }

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 54, height: 54)
                    .background(.white.opacity(0.92))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Share Workout")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.black)

            Spacer()

            HStack(spacing: 0) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "camera")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 48, height: 48)
                }

                if let shareURL {
                    ShareLink(item: shareURL) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 48, height: 48)
                    }
                } else {
                    Button {
                        Task { await renderShareImage() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 48, height: 48)
                    }
                }
            }
            .foregroundStyle(.black)
            .background(.white.opacity(0.92), in: Capsule())
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 14)
    }

    private var poster: some View {
        WorkoutSharePoster(
            detail: detail,
            mode: mode,
            backgroundImage: backgroundImage,
            cityName: cityName
        )
    }

    private var modeControls: some View {
        HStack(spacing: 10) {
            modeButton(.photo, icon: "photo")
            modeButton(.map, icon: "map")
            Spacer()
        }
    }

    private func modeButton(_ value: SharePosterMode, icon: String) -> some View {
        Button {
            mode = value
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(mode == value ? AppColor.accent : AppColor.textSecondary)
                .frame(width: 60, height: 60)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(mode == value ? AppColor.accent : AppColor.divider, lineWidth: mode == value ? 2 : 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var backgroundChoices: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                thumbnail {
                    if let backgroundImage {
                        Image(uiImage: backgroundImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }

            ForEach(SharePosterMode.allCases) { item in
                Button {
                    mode = item
                } label: {
                    thumbnail {
                        SharePosterThumbnail(mode: item)
                    }
                    .overlay(alignment: .topTrailing) {
                        if mode == item {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(AppColor.accent)
                                .padding(6)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func thumbnail<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(height: 92)
            .frame(maxWidth: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhoto,
              let data = try? await selectedPhoto.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }

        backgroundImage = image
        mode = .photo
    }

    private func resolveCityName() async {
        guard let point = detail.route.first else { return }
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return }
        cityName = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea ?? cityName
    }

    @MainActor
    private func renderShareImage() async {
        let content = WorkoutSharePoster(
            detail: detail,
            mode: mode,
            backgroundImage: backgroundImage,
            cityName: cityName
        )
        .frame(width: 1080, height: 1440)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1

        guard let image = renderer.uiImage,
              let data = image.pngData()
        else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HAL9000-Workout-\(detail.id).png")
        try? data.write(to: url, options: .atomic)
        shareURL = url
    }
}

private enum SharePosterMode: String, CaseIterable, Identifiable {
    case photo
    case map

    var id: String { rawValue }
}

private struct WorkoutSharePoster: View {
    let detail: WorkoutDetail
    let mode: SharePosterMode
    let backgroundImage: UIImage?
    let cityName: String

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                background
                LinearGradient(
                    colors: [.black.opacity(0.62), .black.opacity(0.08), .black.opacity(0.76)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading) {
                    topMeta
                    Spacer()
                    bottomStats(width: geometry.size.width)
                }
                .padding(.horizontal, geometry.size.width * 0.055)
                .padding(.vertical, geometry.size.height * 0.04)

                if !detail.route.isEmpty {
                    RouteOverlayShape(points: detail.route)
                        .stroke(.white, style: StrokeStyle(lineWidth: max(geometry.size.width * 0.01, 4), lineCap: .round, lineJoin: .round))
                        .frame(width: geometry.size.width * 0.28, height: geometry.size.height * 0.27)
                        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
                        .position(x: geometry.size.width * 0.77, y: geometry.size.height * 0.66)
                }
            }
            .clipped()
        }
        .background(.black)
    }

    @ViewBuilder
    private var background: some View {
        if mode == .photo, let backgroundImage {
            Image(uiImage: backgroundImage)
                .resizable()
                .scaledToFill()
        } else {
            ShareMapStyleBackground(points: detail.route)
        }
    }

    private var topMeta: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("HAL9000")
                    .font(.system(size: 42, weight: .bold))
                Text(detail.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 30, weight: .medium))
            }

            Spacer()

            Label("Ultra", systemImage: "applewatch")
                .font(.system(size: 30, weight: .bold))
        }
        .foregroundStyle(.white)
    }

    private func bottomStats(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            Image(systemName: "figure.run")
                .font(.system(size: 48, weight: .bold))
            Text(cityName)
                .font(.system(size: 58, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            HStack(alignment: .bottom) {
                shareStat("DISTANCE", detail.distanceKm.map { String(format: "%.2f", $0) } ?? "--", "km")
                Spacer()
                shareStat("TIME", shareDurationText(detail.duration), "min")
                Spacer()
                shareStat("AVG. PACE", paceValue, "/km")
            }
            .frame(maxWidth: width * 0.92)
        }
        .foregroundStyle(.white)
    }

    private func shareStat(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 26, weight: .semibold))
                .opacity(0.88)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 48, weight: .bold))
                Text(unit)
                    .font(.system(size: 30, weight: .bold))
            }
        }
    }

    private var paceValue: String {
        detail.paceText
            .replacingOccurrences(of: " /km", with: "")
            .replacingOccurrences(of: ":", with: "'") + "''"
    }
}

private struct ShareMapStyleBackground: View {
    let points: [WorkoutRoutePoint]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color(hex: "395A43"), Color(hex: "182A33")], startPoint: .topLeading, endPoint: .bottomTrailing)
                grid(size: geometry.size)
                RouteOverlayShape(points: points)
                    .stroke(Color(hex: "FF5B2E"), style: StrokeStyle(lineWidth: max(geometry.size.width * 0.012, 5), lineCap: .round, lineJoin: .round))
                    .padding(geometry.size.width * 0.18)
                    .shadow(color: .white.opacity(0.85), radius: 0, x: 0, y: 0)
            }
        }
    }

    private func grid(size: CGSize) -> some View {
        Path { path in
            let step = size.width / 7
            for index in 0...8 {
                let x = CGFloat(index) * step
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.width * 0.24, y: size.height))
            }

            for index in 0...10 {
                let y = CGFloat(index) * step
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y + size.height * 0.08))
            }
        }
        .stroke(.white.opacity(0.16), lineWidth: 4)
    }
}

private struct SharePosterThumbnail: View {
    let mode: SharePosterMode

    var body: some View {
        ZStack {
            if mode == .photo {
                LinearGradient(colors: [Color(hex: "7A4D2E"), Color(hex: "D39B54")], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "photo")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                LinearGradient(colors: [Color(hex: "4E7CA2"), Color(hex: "D7E7D7")], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "map")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

private struct RouteOverlayShape: Shape {
    let points: [WorkoutRoutePoint]

    func path(in rect: CGRect) -> Path {
        guard points.count >= 2 else { return Path() }

        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        guard let minLat = latitudes.min(),
              let maxLat = latitudes.max(),
              let minLon = longitudes.min(),
              let maxLon = longitudes.max()
        else { return Path() }

        let latSpan = max(maxLat - minLat, 0.000001)
        let lonSpan = max(maxLon - minLon, 0.000001)
        let inset = min(rect.width, rect.height) * 0.08
        let drawRect = rect.insetBy(dx: inset, dy: inset)

        func point(for routePoint: WorkoutRoutePoint) -> CGPoint {
            let x = drawRect.minX + CGFloat((routePoint.longitude - minLon) / lonSpan) * drawRect.width
            let y = drawRect.maxY - CGFloat((routePoint.latitude - minLat) / latSpan) * drawRect.height
            return CGPoint(x: x, y: y)
        }

        var path = Path()
        path.move(to: point(for: points[0]))
        for routePoint in points.dropFirst() {
            path.addLine(to: point(for: routePoint))
        }
        return path
    }
}

private func shareDurationText(_ duration: TimeInterval) -> String {
    let minutes = max(Int((duration / 60).rounded()), 0)
    return "\(minutes)"
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
