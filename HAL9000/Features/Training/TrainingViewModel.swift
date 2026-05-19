import Foundation
import SwiftUI

@MainActor
final class TrainingViewModel: ObservableObject {
    @Published var sessions: [TrainingSession] = []
    @Published var weekDays: [TrainingWeekDay] = []
    @Published var summary: WeeklySummary?
    @Published var progress: TrainingProgress?
    @Published var state: ViewState = .idle
    @Published var exportState: TrainingExportViewState = .idle
    @Published var garminExportURL: URL?
    @Published var cacheNotice: String?
    @Published var selectedExportIDs: Set<String> = []

    private let api = APIClient.shared
    private let cache = CacheStore.shared
    private let exportService = TrainingExportService()
    private let healthService: HealthKitServing = HealthKitService.shared
    private let weeklyCacheTTL: TimeInterval = 24 * 60 * 60

    // MARK: - Load

    func load() async {
        state = .loading
        cacheNotice = nil
        let hadCachedData = await loadCachedWeeklyData()

        do {
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
            await mergeCurrentWeekHealthData()
            rebuildWeekDays()
            syncSelectedExportIDs()
            cacheNotice = nil

            // Cache
            let cacheData = WeeklyData(sessions: sessions, summary: summary, progress: progress, weekDays: weekDays)
            await cache.set(cacheData, for: "weekly_data", ttl: weeklyCacheTTL)

            state = sessions.isEmpty ? .empty : .loaded

        } catch {
            // If we have cached data, keep showing it
            if !hadCachedData && sessions.isEmpty {
                await mergeCurrentWeekHealthData()
                rebuildWeekDays()
                syncSelectedExportIDs()
                state = sessions.isEmpty ? .failed(error.localizedDescription) : .loaded
            } else if hadCachedData {
                cacheNotice = "正在显示缓存数据，后台刷新暂时失败。"
                state = sessions.isEmpty ? .empty : .loaded
            }
        }
    }

    func refresh() async {
        await cache.remove("weekly_data")
        garminExportURL = nil
        exportState = .idle
        await load()
    }

    func exportToAppleWatch(_ selectedSessions: [TrainingSession]? = nil) async {
        exportState = .exporting("正在同步到 Apple Watch...")

        do {
            let result = try await exportService.scheduleOnAppleWatch(selectedSessions ?? sessions)
            exportState = .succeeded(result.message)
        } catch {
            exportState = .failed(error.localizedDescription)
        }
    }

    func prepareGarminExport(_ selectedSessions: [TrainingSession]? = nil) {
        exportState = .exporting("正在生成 Garmin TCX...")

        do {
            garminExportURL = try exportService.makeGarminTCXFile(from: selectedSessions ?? sessions)
            exportState = .succeeded("已生成 Garmin TCX 文件，可分享到 Garmin Connect。")
        } catch {
            garminExportURL = nil
            exportState = .failed(error.localizedDescription)
        }
    }

    var exportableSessions: [TrainingSession] {
        sessions
            .filter { !$0.isCompleted }
            .filter { $0.isRunningWorkout }
            .filter { $0.exportDistanceMeters > 0 || $0.exportDurationSeconds > 0 }
            .sorted { $0.date < $1.date }
    }

    var selectedExportSessions: [TrainingSession] {
        exportableSessions.filter { selectedExportIDs.contains($0.id) }
    }

    func toggleExportSelection(_ session: TrainingSession) {
        if selectedExportIDs.contains(session.id) {
            selectedExportIDs.remove(session.id)
        } else {
            selectedExportIDs.insert(session.id)
        }
    }

    func selectAllExportableSessions() {
        selectedExportIDs = Set(exportableSessions.map(\.id))
    }

    func clearExportSelection() {
        selectedExportIDs.removeAll()
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
                zone: item.zone,
                startedAt: nil
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

    private func loadCachedWeeklyData() async -> Bool {
        guard let cached: CachedValue<WeeklyData> = await cache.getIncludingExpired("weekly_data", as: WeeklyData.self) else {
            return false
        }

        sessions = cached.value.sessions
        summary = cached.value.summary
        progress = cached.value.progress
        weekDays = cached.value.weekDays
        await mergeCurrentWeekHealthData()
        if weekDays.isEmpty { rebuildWeekDays() }
        syncSelectedExportIDs()
        cacheNotice = cached.isExpired ? "正在显示缓存数据，数据可能不是最新。" : nil
        state = sessions.isEmpty ? .empty : .loaded
        return true
    }

    private func rebuildWeekDays() {
        let interval = currentWeekInterval()
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "E"

        weekDays = (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: interval.start) ?? interval.start
            let dateKey = dateString(from: date)
            let daySessions = sessions
                .filter { $0.date == dateKey }
                .sorted { lhs, rhs in
                    let left = lhs.startedAt ?? self.date(from: lhs.date) ?? .distantPast
                    let right = rhs.startedAt ?? self.date(from: rhs.date) ?? .distantPast
                    return left < right
                }
            let session = daySessions.first

            return TrainingWeekDay(
                id: dateKey,
                date: date,
                weekday: formatter.string(from: date),
                title: dateTitle(for: date),
                session: session,
                recoveryAdvice: recoveryAdvice(for: date, session: session)
            )
        }
    }

    private func recoveryAdvice(for date: Date, session: TrainingSession?) -> String {
        if let session {
            return session.description ?? "按计划完成，结束后补水、拉伸并观察腿部反馈。"
        }

        if Calendar.current.isDateInToday(date) {
            return "休息日，散步 20-30 分钟，晚上早点睡。"
        }

        return "休息日，保持轻量活动，优先恢复。"
    }

    private func dateTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func syncSelectedExportIDs() {
        let exportableIDs = Set(exportableSessions.map(\.id))
        if selectedExportIDs.isEmpty {
            selectedExportIDs = exportableIDs
        } else {
            selectedExportIDs = selectedExportIDs.intersection(exportableIDs)
        }
    }

    private func mergeCurrentWeekHealthData() async {
        let interval = currentWeekInterval()
        guard let healthWorkouts = try? await healthService.fetchRunningWorkoutSummaries(from: interval.start, to: interval.end),
              !healthWorkouts.isEmpty
        else { return }

        let existingIDs = Set(sessions.map(\.id))
        let healthSessions = healthWorkouts
            .filter { !existingIDs.contains($0.id) }
            .map(trainingSession)

        if !healthSessions.isEmpty {
            sessions = (sessions + healthSessions).sorted { lhs, rhs in
                let leftDate = lhs.startedAt ?? date(from: lhs.date) ?? .distantPast
                let rightDate = rhs.startedAt ?? date(from: rhs.date) ?? .distantPast
                return leftDate > rightDate
            }
        }

        let healthDistanceMeters = healthWorkouts.reduce(0) { total, workout in
            total + ((workout.distanceKm ?? 0) * 1000)
        }
        let healthDurationSeconds = Int(healthWorkouts.reduce(0) { total, workout in
            total + workout.durationMinutes * 60
        })
        let currentCompleted = progress?.completedDistance ?? summary?.totalDistance ?? 0
        let completedDistance = max(currentCompleted, healthDistanceMeters)
        let targetDistance = progress?.targetDistance ?? plannedDistanceKm(from: sessions) * 1000
        let remainingDistance = max(targetDistance - completedDistance, 0)
        let completedCount = max(
            sessions.filter(\.isCompleted).count,
            healthWorkouts.count
        )

        progress = TrainingProgress(
            targetDistance: targetDistance,
            completedDistance: completedDistance,
            remainingDistance: remainingDistance,
            completedSessions: completedCount,
            plannedSessions: sessions.count,
            guidance: trainingGuidance(
                completedDistance: completedDistance,
                targetDistance: targetDistance,
                remainingDistance: remainingDistance,
                phase: summary?.phase
            )
        )

        if let summary {
            self.summary = WeeklySummary(
                weekStart: summary.weekStart,
                totalDistance: completedDistance,
                totalDuration: max(summary.totalDuration, healthDurationSeconds),
                totalActivities: max(summary.totalActivities, completedCount),
                phase: summary.phase,
                phaseDescription: summary.phaseDescription
            )
        } else {
            self.summary = WeeklySummary(
                weekStart: dateString(from: interval.start),
                totalDistance: completedDistance,
                totalDuration: healthDurationSeconds,
                totalActivities: healthWorkouts.count,
                phase: nil,
                phaseDescription: nil
            )
        }
    }

    private func trainingSession(from workout: TodayWorkoutSummary) -> TrainingSession {
        TrainingSession(
            id: workout.id,
            name: workout.title,
            type: "Run",
            date: dateString(from: workout.startedAt),
            distance: (workout.distanceKm ?? 0) * 1000,
            duration: Int(workout.durationMinutes * 60),
            averageHeartrate: nil,
            averagePace: nil,
            description: "Apple 健康记录",
            status: "completed",
            plannedDistance: nil,
            plannedDuration: nil,
            actualDistance: workout.distanceKm.map { $0 * 1000 },
            actualDuration: Int(workout.durationMinutes * 60),
            zone: nil,
            startedAt: workout.startedAt
        )
    }

    private func currentWeekInterval() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let dayStart = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: dayStart)
        let daysFromMonday = (weekday + 5) % 7
        let start = calendar.date(byAdding: .day, value: -daysFromMonday, to: dayStart) ?? dayStart
        return (start, now)
    }

    private func date(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
    let weekDays: [TrainingWeekDay]

    init(sessions: [TrainingSession], summary: WeeklySummary?, progress: TrainingProgress?, weekDays: [TrainingWeekDay] = []) {
        self.sessions = sessions
        self.summary = summary
        self.progress = progress
        self.weekDays = weekDays
    }
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
