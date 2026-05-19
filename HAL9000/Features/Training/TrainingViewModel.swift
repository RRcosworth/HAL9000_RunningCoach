import Foundation
import SwiftUI

@MainActor
final class TrainingViewModel: ObservableObject {
    @Published var sessions: [TrainingSession] = []
    @Published var summary: WeeklySummary?
    @Published var progress: TrainingProgress?
    @Published var state: ViewState = .idle
    @Published var exportState: TrainingExportViewState = .idle
    @Published var garminExportURL: URL?

    private let api = APIClient.shared
    private let cache = CacheStore.shared
    private let exportService = TrainingExportService()

    // MARK: - Load

    func load() async {
        state = .loading

        do {
            // Try cache first if offline
            if let cached: WeeklyData = await cache.get("weekly_data", as: WeeklyData.self) {
                sessions = cached.sessions
                summary = cached.summary
                progress = cached.progress
                if state == .loading { state = .loaded }
            }

            // Fetch fresh data
            await api.updateBaseURL(UserSessionStore.shared.resolvedBaseURL)

            let dateStr = ISO8601DateFormatter().string(from: Date())
            let queryDate = String(dateStr.prefix(10))

            let endpoint = Endpoint(
                path: "api/weekly",
                queryItems: [URLQueryItem(name: "date", value: queryDate)]
            )

            let raw: WeeklyRawResponse = try await api.send(endpoint)
            let parsed = parseResponse(raw)

            sessions = parsed.sessions
            summary = parsed.summary
            progress = parsed.progress

            // Cache
            let cacheData = WeeklyData(sessions: sessions, summary: summary, progress: progress)
            await cache.set(cacheData, for: "weekly_data", ttl: 300)

            state = sessions.isEmpty ? .empty : .loaded

        } catch {
            // If we have cached data, keep showing it
            if sessions.isEmpty {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func refresh() async {
        await cache.remove("weekly_data")
        garminExportURL = nil
        exportState = .idle
        await load()
    }

    func exportToAppleWatch() async {
        exportState = .exporting("正在同步到 Apple Watch...")

        do {
            let result = try await exportService.scheduleOnAppleWatch(sessions)
            exportState = .succeeded(result.message)
        } catch {
            exportState = .failed(error.localizedDescription)
        }
    }

    func prepareGarminExport() {
        exportState = .exporting("正在生成 Garmin TCX...")

        do {
            garminExportURL = try exportService.makeGarminTCXFile(from: sessions)
            exportState = .succeeded("已生成 Garmin TCX 文件，可分享到 Garmin Connect。")
        } catch {
            garminExportURL = nil
            exportState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Parse

    private func parseResponse(_ raw: WeeklyRawResponse) -> (sessions: [TrainingSession], summary: WeeklySummary?, progress: TrainingProgress?) {
        let sessions = (raw.plan ?? []).map { item in
            let distanceKm = item.actual_distance_km ?? item.planned_distance_km ?? 0
            let durationMinutes = item.actual_dur_min ?? parseDurationMinutes(item.duration)
            let plannedDistance = (item.planned_distance_km ?? 0) * 1000
            let actualDistance = item.actual_distance_km.map { $0 * 1000 }
            let plannedDuration = parseDurationMinutes(item.duration) * 60
            let actualDuration = item.actual_dur_min.map { $0 * 60 }

            return TrainingSession(
                id: item.activity_ids?.first ?? item.iso_date ?? UUID().uuidString,
                name: sessionName(for: item),
                type: item.type ?? "Run",
                date: item.iso_date ?? item.date ?? "",
                distance: distanceKm * 1000,
                duration: durationMinutes * 60,
                averageHeartrate: item.actual_hr.map(Double.init),
                averagePace: nil,
                description: item.detail ?? item.reason,
                status: item.status,
                plannedDistance: plannedDistance > 0 ? plannedDistance : nil,
                plannedDuration: plannedDuration > 0 ? plannedDuration : nil,
                actualDistance: actualDistance,
                actualDuration: actualDuration,
                zone: item.zone
            )
        }

        let runTotals = raw.activities?.run
        let completedDistance = (runTotals?.distance_km ?? raw.plan_summary?.completed_km ?? completedDistanceKm(from: sessions)) * 1000
        let targetDistance = (raw.plan_summary?.target_km ?? plannedDistanceKm(from: sessions)) * 1000
        let remainingDistance = (raw.plan_summary?.remaining_km.map { $0 * 1000 }) ?? max(targetDistance - completedDistance, 0)

        let summary = WeeklySummary(
            weekStart: raw.week_range ?? raw.week_label ?? "",
            totalDistance: completedDistance,
            totalDuration: runTotals?.duration_sec ?? completedDuration(from: sessions),
            totalActivities: runTotals?.count ?? sessions.count,
            phase: raw.diagnosis?.phase_name ?? raw.diagnosis?.phase,
            phaseDescription: raw.plan_summary?.target_reason ?? raw.headline?.strippingHTML()
        )

        let progress = TrainingProgress(
            targetDistance: targetDistance,
            completedDistance: completedDistance,
            remainingDistance: remainingDistance,
            completedSessions: sessions.filter(\.isCompleted).count,
            plannedSessions: sessions.count,
            guidance: trainingGuidance(
                completedDistance: completedDistance,
                targetDistance: targetDistance,
                remainingDistance: remainingDistance,
                phase: raw.diagnosis?.phase_name ?? raw.diagnosis?.phase
            )
        )

        return (sessions, summary, progress)
    }

    private func sessionName(for item: RawPlanItem) -> String {
        if let day = item.day, let date = item.date {
            return "\(day) \(date)"
        }

        if let type = item.type {
            return type.capitalized
        }

        return "训练"
    }

    private func parseDurationMinutes(_ duration: String?) -> Int {
        guard let duration, !duration.isEmpty, duration != "—" else { return 0 }

        if duration.hasSuffix("min"),
           let minutes = Int(duration.replacingOccurrences(of: "min", with: "")) {
            return minutes
        }

        if duration.contains("h") {
            let parts = duration
                .replacingOccurrences(of: "m", with: "")
                .split(separator: "h")

            let hours = parts.first.flatMap { Int($0) } ?? 0
            let minutes = parts.dropFirst().first.flatMap { Int($0) } ?? 0
            return hours * 60 + minutes
        }

        return 0
    }

    private func plannedDistanceKm(from sessions: [TrainingSession]) -> Double {
        sessions.reduce(0) { total, session in
            total + ((session.plannedDistance ?? session.distance) / 1000)
        }
    }

    private func completedDistanceKm(from sessions: [TrainingSession]) -> Double {
        sessions
            .filter(\.isCompleted)
            .reduce(0) { total, session in
                total + ((session.actualDistance ?? session.distance) / 1000)
            }
    }

    private func completedDuration(from sessions: [TrainingSession]) -> Int {
        sessions
            .filter(\.isCompleted)
            .reduce(0) { total, session in
                total + (session.actualDuration ?? session.duration)
            }
    }

    private func trainingGuidance(completedDistance: Double, targetDistance: Double, remainingDistance: Double, phase: String?) -> String {
        guard targetDistance > 0 else {
            return "等待 Hermes 生成本周训练目标。先保持轻松跑和规律恢复。"
        }

        let ratio = completedDistance / targetDistance
        let phaseText = phase.map { "\($0)阶段" } ?? "本周"

        if ratio >= 1 {
            return "\(phaseText)目标已完成。后续以恢复跑、拉伸和睡眠为主，避免额外堆跑量。"
        }

        if ratio >= 0.72 {
            return "\(phaseText)进度良好，剩余 \(String(format: "%.1f", remainingDistance / 1000)) km 建议拆成轻松跑完成。"
        }

        if ratio >= 0.4 {
            return "\(phaseText)还有提升空间，优先完成下一次计划训练，不建议一次性补齐跑量。"
        }

        return "\(phaseText)进度偏慢，先安排低强度有氧，质量课等身体状态稳定后再做。"
    }
}

// MARK: - Raw API Response Models

struct WeeklyRawResponse: Decodable {
    let week_label: String?
    let week_range: String?
    let activities: RawActivities?
    let diagnosis: RawDiagnosis?
    let plan: [RawPlanItem]?
    let plan_summary: RawPlanSummary?
    let headline: String?
}

struct RawActivities: Decodable {
    let run: RawActivityTotals?
    let ride: RawActivityTotals?
    let swim: RawActivityTotals?
}

struct RawActivityTotals: Decodable {
    let count: Int?
    let distance_km: Double?
    let duration_sec: Int?
    let duration_fmt: String?
}

struct RawDiagnosis: Decodable {
    let phase: String?
    let phase_name: String?
    let intensity: String?
    let intensity_name: String?
}

struct RawPlanItem: Decodable {
    let activity_ids: [String]?
    let actual_distance_km: Double?
    let actual_dur_min: Int?
    let actual_hr: Int?
    let actual_pace: String?
    let adjusted: Bool?
    let date: String?
    let day: String?
    let detail: String?
    let duration: String?
    let iso_date: String?
    let planned_distance_km: Double?
    let reason: String?
    let source: String?
    let status: String?
    let type: String?
    let zone: String?
}

struct RawPlanSummary: Decodable {
    let completed_km: Double?
    let remaining_km: Double?
    let target_km: Double?
    let target_reason: String?
}

private extension String {
    func strippingHTML() -> String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Cache Model

struct WeeklyData: Codable {
    let sessions: [TrainingSession]
    let summary: WeeklySummary?
    let progress: TrainingProgress?
}

enum TrainingExportViewState: Equatable {
    case idle
    case exporting(String)
    case succeeded(String)
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            return "将本周未完成跑步课表同步到 Apple Watch，或导出 TCX 给 Garmin Connect。"
        case .exporting(let message), .succeeded(let message), .failed(let message):
            return message
        }
    }
}
