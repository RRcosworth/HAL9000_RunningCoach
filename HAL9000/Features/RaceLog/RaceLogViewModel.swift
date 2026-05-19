import Foundation

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
