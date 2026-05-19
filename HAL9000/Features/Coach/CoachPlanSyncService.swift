import Foundation

struct CoachPlanSyncService {
    func sessions(from patch: CoachPlanPatch) -> [TrainingSession] {
        patch.sessions.enumerated().map { index, session in
            TrainingSession(
                id: "coach-\(patch.weekStart ?? "week")-\(index)",
                name: session.day.map { "\($0) \(session.type)" } ?? session.type,
                type: session.type,
                date: patch.weekStart ?? "",
                distance: (session.distanceKm ?? 0) * 1000,
                duration: 0,
                averageHeartrate: nil,
                averagePace: nil,
                description: session.detail,
                status: "planned",
                plannedDistance: session.distanceKm.map { $0 * 1000 },
                plannedDuration: nil,
                actualDistance: nil,
                actualDuration: nil,
                zone: session.zone,
                startedAt: nil
            )
        }
    }
}
