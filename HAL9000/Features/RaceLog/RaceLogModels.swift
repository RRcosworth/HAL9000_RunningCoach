import CoreLocation
import Foundation

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

extension ISO8601DateFormatter {
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
