import CoreLocation
import Foundation

actor IntervalsICUService {
    private var baseURL: URL {
        guard let url = URL(string: "https://intervals.icu") else {
            fatalError("Intervals.icu base URL is invalid")
        }
        return url
    }

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
                "max_heartrate",
                "total_elevation_gain",
                "average_cadence",
                "calories",
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

        return try JSONDecoder().decode([IntervalsActivity].self, from: data)
    }

    func fetchActivityDetail(apiKey: String, activityId: String) async throws -> IntervalsActivityDetail {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/activity/\(activityId)"))
        request.setValue(authorizationHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validate(response)

        return try JSONDecoder().decode(IntervalsActivityDetail.self, from: data)
    }

    func fetchStartCoordinate(apiKey: String, activityId: String) async throws -> CLLocationCoordinate2D? {
        try await fetchRouteStreams(apiKey: apiKey, activityId: activityId).coordinates.first
    }

    func fetchRouteStreams(apiKey: String, activityId: String) async throws -> RaceRouteStreams {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/v1/activity/\(activityId)/streams"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "types", value: "latlng,altitude")
        ]

        guard let url = components?.url else { throw IntervalsICUError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(authorizationHeader(apiKey: apiKey), forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validate(response)

        let streams = try JSONDecoder().decode([IntervalsStream].self, from: data)
        return RaceRouteStreams(
            coordinates: streams.first(where: { $0.type == "latlng" })?.coordinates ?? [],
            elevationGain: streams.first(where: { $0.type == "altitude" })?.smoothedElevationGain
        )
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
