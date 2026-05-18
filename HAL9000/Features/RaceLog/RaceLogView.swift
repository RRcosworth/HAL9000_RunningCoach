import MapKit
import SwiftUI

struct RaceLogView: View {
    @StateObject private var viewModel = RaceLogViewModel()
    @AppStorage("intervalsApiKey") private var intervalsApiKey = ""
    @AppStorage("intervalsAthleteId") private var intervalsAthleteId = ""
    @State private var showingSettings = false

    private let defaultIntervalsApiKey = ""
    private let defaultIntervalsAthleteId = ""

    var body: some View {
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
        .sheet(isPresented: $showingSettings) {
            intervalsSettings
        }
        .task {
            configureIntervalsDefaultsIfNeeded()
            await loadRaces()
        }
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
                    Text("我会从活动名称和标签里识别 race、marathon、5K、10K、半马、全马、比赛等关键词。")
                        .font(AppTypography.footnote)
                        .foregroundStyle(AppColor.textSecondary)
                }
            } else {
                ForEach(snapshot.races) { race in
                    raceRow(race)
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
                        showingSettings = false
                        Task { await loadRaces() }
                    }
                }
            }
        }
        .supportsSwipeBack()
    }

    private func raceRow(_ race: RaceActivity) -> some View {
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
                        Text(race.dateText)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    HStack(spacing: 8) {
                        infoChip(race.distanceText, icon: "ruler")
                        infoChip(race.durationText, icon: "stopwatch")
                        infoChip(race.paceText, icon: "speedometer")
                    }

                    if let location = race.locationText {
                        Label(location, systemImage: "location")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }
        }
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

    private func configureIntervalsDefaultsIfNeeded() {
        if intervalsApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            intervalsApiKey = defaultIntervalsApiKey
        }

        if intervalsAthleteId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            intervalsAthleteId = defaultIntervalsAthleteId
        }
    }
}

struct RaceMapView: View {
    let races: [RaceActivity]
    @State private var position: MapCameraPosition

    init(races: [RaceActivity]) {
        self.races = races
        _position = State(initialValue: .region(Self.region(for: races)))
    }

    var body: some View {
        Map(position: $position) {
            ForEach(races) { race in
                if let coordinate = race.coordinate {
                    Marker(race.name, systemImage: "flag.checkered", coordinate: coordinate)
                        .tint(AppColor.accent)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onChange(of: races) { _, newValue in
            position = .region(Self.region(for: newValue))
        }
    }

    private static func region(for races: [RaceActivity]) -> MKCoordinateRegion {
        let coordinates = races.compactMap(\.coordinate)
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
                span: MKCoordinateSpan(latitudeDelta: 24, longitudeDelta: 24)
            )
        }

        guard coordinates.count > 1 else {
            return MKCoordinateRegion(
                center: coordinates[0],
                span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
            )
        }

        let minLat = coordinates.map(\.latitude).min() ?? 0
        let maxLat = coordinates.map(\.latitude).max() ?? 0
        let minLon = coordinates.map(\.longitude).min() ?? 0
        let maxLon = coordinates.map(\.longitude).max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.2),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.2)
        )

        return MKCoordinateRegion(center: center, span: span)
    }
}

@MainActor
final class RaceLogViewModel: ObservableObject {
    @Published var state: RaceLogState = .idle
    private let service = IntervalsICUService()

    func load(apiKey: String, athleteId: String) async {
        guard !apiKey.isEmpty else {
            state = .idle
            return
        }

        state = .loading

        do {
            let resolvedAthlete = athleteId.isEmpty ? try await service.fetchAthleteId(apiKey: apiKey) : athleteId
            let activities = try await service.fetchActivities(apiKey: apiKey, athleteId: resolvedAthlete)
            var races = activities
                .filter(\.isRace)
                .sorted { $0.startDate > $1.startDate }
                .map(RaceActivity.init(raw:))

            for index in races.indices where races[index].coordinate == nil {
                if let coordinate = try? await service.fetchStartCoordinate(apiKey: apiKey, activityId: races[index].id) {
                    races[index] = races[index].withCoordinate(coordinate)
                }
            }

            state = .loaded(RaceLogSnapshot(athleteId: resolvedAthlete, races: races))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

enum RaceLogState: Equatable {
    case idle
    case loading
    case loaded(RaceLogSnapshot)
    case failed(String)
}

struct RaceLogSnapshot: Equatable {
    let athleteId: String?
    let races: [RaceActivity]

    var mappedRaces: [RaceActivity] {
        races.filter { $0.coordinate != nil }
    }

    var totalDistanceText: String {
        let distance = races.map(\.distanceMeters).reduce(0, +) / 1000
        return String(format: "%.1f km", distance)
    }

    var fastestPaceText: String {
        let paces = races.compactMap(\.paceSecondsPerKm)
        guard let fastest = paces.min() else { return "--" }
        let minutes = Int(fastest) / 60
        let seconds = Int(fastest) % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }

    var mapNote: String {
        if mappedRaces.count == races.count {
            return "所有识别到的比赛都有起点坐标，已标记在地图上。"
        }

        return "有些 Intervals.icu 活动没有返回起点坐标，会保留在列表但不显示地图标记。"
    }
}

struct RaceActivity: Identifiable, Equatable {
    let id: String
    let name: String
    let startDate: Date
    let distanceMeters: Double
    let movingTimeSeconds: Int
    let coordinate: CLLocationCoordinate2D?
    let locationText: String?

    init(raw: IntervalsActivity) {
        id = raw.id
        name = raw.name ?? "Race"
        startDate = raw.startDate
        distanceMeters = raw.distance ?? 0
        movingTimeSeconds = raw.movingTime ?? raw.elapsedTime ?? 0
        coordinate = raw.coordinate ?? raw.cityCoordinate
        locationText = raw.location
    }

    private init(
        id: String,
        name: String,
        startDate: Date,
        distanceMeters: Double,
        movingTimeSeconds: Int,
        coordinate: CLLocationCoordinate2D?,
        locationText: String?
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.distanceMeters = distanceMeters
        self.movingTimeSeconds = movingTimeSeconds
        self.coordinate = coordinate
        self.locationText = locationText
    }

    func withCoordinate(_ coordinate: CLLocationCoordinate2D) -> RaceActivity {
        RaceActivity(
            id: id,
            name: name,
            startDate: startDate,
            distanceMeters: distanceMeters,
            movingTimeSeconds: movingTimeSeconds,
            coordinate: coordinate,
            locationText: locationText
        )
    }

    static func == (lhs: RaceActivity, rhs: RaceActivity) -> Bool {
        lhs.id == rhs.id
    }

    var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/M/d"
        return formatter.string(from: startDate)
    }

    var distanceText: String {
        String(format: "%.1f km", distanceMeters / 1000)
    }

    var durationText: String {
        let hours = movingTimeSeconds / 3600
        let minutes = (movingTimeSeconds % 3600) / 60
        return hours > 0 ? "\(hours)h\(minutes)m" : "\(minutes)min"
    }

    var paceSecondsPerKm: Double? {
        guard distanceMeters > 0, movingTimeSeconds > 0 else { return nil }
        return Double(movingTimeSeconds) / (distanceMeters / 1000)
    }

    var paceText: String {
        guard let pace = paceSecondsPerKm else { return "--" }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d/km", minutes, seconds)
    }
}

actor IntervalsICUService {
    private let baseURL = URL(string: "https://intervals.icu")!
    private let session = URLSession.shared

    func fetchAthleteId(apiKey: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/athlete/me"))
        request.setValue(authorizationHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validate(response)

        let athlete = try JSONDecoder().decode(IntervalsAthlete.self, from: data)
        return athlete.id
    }

    func fetchActivities(apiKey: String, athleteId: String) async throws -> [IntervalsActivity] {
        let newest = Date()
        let oldest = Calendar.current.date(byAdding: .year, value: -8, to: newest) ?? newest
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v1/athlete/\(athleteId)/activities"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "oldest", value: isoDate(oldest)),
            URLQueryItem(name: "newest", value: isoDate(newest)),
            URLQueryItem(name: "fields", value: [
                "id",
                "name",
                "type",
                "start_date_local",
                "start_date",
                "distance",
                "icu_distance",
                "moving_time",
                "elapsed_time",
                "average_heartrate",
                "start_latlng",
                "end_latlng",
                "latlng",
                "location",
                "tags",
                "category",
                "sub_type",
                "race"
            ].joined(separator: ","))
        ]

        guard let url = components?.url else { throw IntervalsICUError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(authorizationHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validate(response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = ISO8601DateFormatter.intervalsWithFractionalSeconds.date(from: value)
                ?? ISO8601DateFormatter.intervals.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
        }

        return try decoder.decode([IntervalsActivity].self, from: data)
    }

    func fetchStartCoordinate(apiKey: String, activityId: String) async throws -> CLLocationCoordinate2D? {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v1/activity/\(activityId)/streams"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "types", value: "latlng")
        ]

        guard let url = components?.url else { throw IntervalsICUError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(authorizationHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validate(response)

        let streams = try JSONDecoder().decode([IntervalsStream].self, from: data)
        return streams.first(where: { $0.type == "latlng" })?.startCoordinate
    }

    private func authorizationHeader(apiKey: String) -> String {
        let token = "API_KEY:\(apiKey)"
        let encoded = Data(token.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw IntervalsICUError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw IntervalsICUError.unauthorized }
            throw IntervalsICUError.statusCode(http.statusCode)
        }
    }

    private func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct IntervalsAthlete: Decodable {
    let id: String
}

struct IntervalsActivity: Decodable {
    let id: String
    let name: String?
    let type: String?
    let startDate: Date
    let distance: Double?
    let movingTime: Int?
    let elapsedTime: Int?
    let startLatLng: [Double]?
    let endLatLng: [Double]?
    let latLng: [Double]?
    let location: String?
    let tags: [String]?
    let category: String?
    let subType: String?
    let race: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case startDateLocal = "start_date_local"
        case startDate = "start_date"
        case distance
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case startLatLng = "start_latlng"
        case endLatLng = "end_latlng"
        case latLng = "latlng"
        case location
        case tags
        case category
        case subType = "sub_type"
        case race
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        startDate = try container.decodeFlexibleDateIfPresent(forKey: .startDateLocal)
            ?? container.decodeFlexibleDateIfPresent(forKey: .startDate)
            ?? Date.distantPast
        distance = try container.decodeFlexibleDoubleIfPresent(forKey: .distance)
        movingTime = try container.decodeIfPresent(Int.self, forKey: .movingTime)
        elapsedTime = try container.decodeIfPresent(Int.self, forKey: .elapsedTime)
        startLatLng = try container.decodeCoordinateArrayIfPresent(forKey: .startLatLng)
        endLatLng = try container.decodeCoordinateArrayIfPresent(forKey: .endLatLng)
        latLng = try container.decodeCoordinateArrayIfPresent(forKey: .latLng)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        subType = try container.decodeIfPresent(String.self, forKey: .subType)
        race = try container.decodeIfPresent(Bool.self, forKey: .race)
    }

    var coordinate: CLLocationCoordinate2D? {
        let pair = startLatLng ?? latLng ?? endLatLng
        guard let pair, pair.count >= 2 else { return nil }
        return Self.validCoordinate(latitude: pair[0], longitude: pair[1], name: name)
    }

    var cityCoordinate: CLLocationCoordinate2D? {
        let haystack = [name, location, category]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        for city in Self.cityCoordinates where haystack.contains(city.keyword) {
            return city.coordinate
        }

        return nil
    }

    var isRace: Bool {
        let typeValue = (type ?? "").lowercased()
        guard typeValue == "run" || typeValue == "virtualrun" else { return false }

        if race == true { return true }

        let haystack = ([name, category, subType] + (tags ?? []).map(Optional.some))
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        let keywords = [
            "race",
            "marathon",
            "half marathon",
            "10k",
            "5k",
            "trail race",
            "比赛",
            "半马",
            "全马",
            "马拉松",
            "越野赛",
            "竞赛",
            "race"
        ]

        return keywords.contains { haystack.contains($0) }
    }

    private static func validCoordinate(latitude: Double, longitude: Double, name: String?) -> CLLocationCoordinate2D? {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            return nil
        }

        let lowercasedName = (name ?? "").lowercased()
        let isChinaRace = cityCoordinates.contains { lowercasedName.contains($0.keyword) }
        if isChinaRace, !(70...140).contains(longitude) {
            return nil
        }

        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static let cityCoordinates: [(keyword: String, coordinate: CLLocationCoordinate2D)] = [
        ("湘湖", CLLocationCoordinate2D(latitude: 30.153, longitude: 120.226)),
        ("hangzhou", CLLocationCoordinate2D(latitude: 30.246, longitude: 120.210)),
        ("杭州", CLLocationCoordinate2D(latitude: 30.246, longitude: 120.210)),
        ("shaoxing", CLLocationCoordinate2D(latitude: 30.030, longitude: 120.580)),
        ("绍兴", CLLocationCoordinate2D(latitude: 30.030, longitude: 120.580)),
        ("dongcheng", CLLocationCoordinate2D(latitude: 39.930, longitude: 116.416)),
        ("beijing", CLLocationCoordinate2D(latitude: 39.904, longitude: 116.407)),
        ("北京", CLLocationCoordinate2D(latitude: 39.904, longitude: 116.407)),
        ("suzhou", CLLocationCoordinate2D(latitude: 31.299, longitude: 120.585)),
        ("苏州", CLLocationCoordinate2D(latitude: 31.299, longitude: 120.585)),
        ("nantong", CLLocationCoordinate2D(latitude: 31.980, longitude: 120.894)),
        ("南通", CLLocationCoordinate2D(latitude: 31.980, longitude: 120.894)),
        ("wuxi", CLLocationCoordinate2D(latitude: 31.491, longitude: 120.312)),
        ("无锡", CLLocationCoordinate2D(latitude: 31.491, longitude: 120.312))
    ]
}

struct IntervalsStream: Decodable {
    let type: String
    let data: [Double]

    var startCoordinate: CLLocationCoordinate2D? {
        guard data.count >= 4 else { return nil }
        let longitudeStartIndex = data.count / 2
        guard longitudeStartIndex < data.count else { return nil }

        let latitude = data[0]
        let longitude = data[longitudeStartIndex]
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        guard abs(longitude) > 90 else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum IntervalsICUError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case statusCode(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Intervals.icu URL 无效"
        case .invalidResponse:
            return "Intervals.icu 响应异常"
        case .unauthorized:
            return "API Key 无效，请在 Intervals.icu 设置页重新生成"
        case .statusCode(let code):
            return "Intervals.icu 返回错误 \(code)"
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Double.self, forKey: key) {
            return String(value)
        }
        throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "Missing id"))
    }

    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decode(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    func decodeFlexibleDateIfPresent(forKey key: Key) throws -> Date? {
        guard let value = try? decode(String.self, forKey: key), !value.isEmpty else {
            return nil
        }

        if let date = ISO8601DateFormatter.intervalsWithFractionalSeconds.date(from: value)
            ?? ISO8601DateFormatter.intervals.date(from: value)
            ?? DateFormatter.intervalsLocalDateTime.date(from: value) {
            return date
        }

        return nil
    }

    func decodeCoordinateArrayIfPresent(forKey key: Key) throws -> [Double]? {
        if let value = try? decode([Double].self, forKey: key) {
            return value
        }
        if let stringValue = try? decode(String.self, forKey: key) {
            let values = stringValue
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                .split(separator: ",")
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            return values.isEmpty ? nil : values
        }
        return nil
    }
}

private extension ISO8601DateFormatter {
    static let intervalsWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let intervals: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private extension DateFormatter {
    static let intervalsLocalDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}
