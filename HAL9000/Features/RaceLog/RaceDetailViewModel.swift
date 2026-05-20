import CoreLocation
import Foundation

enum RaceDetailState: Equatable {
    case idle
    case loading
    case loaded
    case partial(String)
}

@MainActor
final class RaceDetailViewModel: ObservableObject {
    @Published var state: RaceDetailState = .idle
    @Published var race: RaceActivity
    @Published var coordinates: [CLLocationCoordinate2D] = []
    @Published var splits: [IntervalsSplit] = []

    private let service = IntervalsICUService()

    init(race: RaceActivity) {
        self.race = race
    }

    func load(apiKey: String) async {
        let trimmedApiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedApiKey.isEmpty else {
            state = .loaded
            return
        }

        state = .loading

        async let detailResult: Result<IntervalsActivityDetail, Error> = capture {
            try await service.fetchActivityDetail(apiKey: trimmedApiKey, activityId: race.id)
        }
        async let routeResult: Result<RaceRouteStreams, Error> = capture {
            try await service.fetchRouteStreams(apiKey: trimmedApiKey, activityId: race.id)
        }

        let detail = await detailResult
        let route = await routeResult

        if case .success(let detailValue) = detail {
            race = race.withDetail(detailValue)
            splits = detailValue.splits ?? []
        }

        if case .success(let routeValue) = route {
            coordinates = routeValue.coordinates
            race = race.withRouteElevationGain(routeValue.elevationGain)
        }

        switch (detail, route) {
        case (.success, .success):
            state = .loaded
        case (.failure(let error), .failure):
            state = .partial(error.localizedDescription)
        case (.failure(let error), .success), (.success, .failure(let error)):
            state = .partial(error.localizedDescription)
        }
    }

    private func capture<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }
}
