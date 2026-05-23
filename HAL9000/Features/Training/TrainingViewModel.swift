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
        resetPreparedExport()
        if selectedExportIDs.contains(session.id) {
            selectedExportIDs.remove(session.id)
        } else {
            selectedExportIDs.insert(session.id)
        }
    }

    func selectAllExportableSessions() {
        resetPreparedExport()
        selectedExportIDs = Set(exportableSessions.map(\.id))
    }

    func clearExportSelection() {
        resetPreparedExport()
        selectedExportIDs.removeAll()
    }

    // MARK: - Parse

    private func parseResponse(_ raw: WeeklyRawResponse) -> (sessions: [TrainingSession], summary: WeeklySummary?, progress: TrainingProgress?) {
        let sessions = (raw.plan ?? []).compactMap { item -> TrainingSession? in
            let type = item.type ?? "Run"
            let status = item.status
            let distanceKm = item.actual_distance_km ?? item.planned_distance_km ?? 0
            let durationMinutes = item.actual_dur_min ?? parseDurationMinutes(item.duration)
            let plannedDistance = (item.planned_distance_km ?? 0) * 1000
            let actualDistance = item.actual_distance_km.map { $0 * 1000 }
            let plannedDuration = parseDurationMinutes(item.duration) * 60
            let actualDuration = item.actual_dur_min.map { $0 * 60 }
            let hasActualWorkout = (actualDistance ?? 0) > 0 || (actualDuration ?? 0) > 0
            let hasPlannedWorkout = plannedDistance > 0 || plannedDuration > 0
            let isRest = type.lowercased() == "rest" || status?.lowercased().contains("rest") == true

            guard hasActualWorkout || hasPlannedWorkout || isRest else {
                return nil
            }

            return TrainingSession(
                id: item.activity_ids?.first ?? item.iso_date ?? UUID().uuidString,
                name: sessionName(for: item),
                type: type,
                date: item.iso_date ?? item.date ?? "",
                distance: distanceKm * 1000,
                duration: durationMinutes * 60,
                averageHeartrate: item.actual_hr.map(Double.init),
                averagePace: nil,
                description: item.detail ?? item.reason,
                status: status,
                plannedDistance: plannedDistance > 0 ? plannedDistance : nil,
                plannedDuration: plannedDuration > 0 ? plannedDuration : nil,
                actualDistance: actualDistance,
                actualDuration: actualDuration,
                zone: item.zone,
                startedAt: nil
            )
        }
        let normalizedSessions = normalizeSessions(sessions)

        let runTotals = raw.activities?.run
        let completedDistance = (runTotals?.distance_km ?? raw.plan_summary?.completed_km ?? completedDistanceKm(from: normalizedSessions)) * 1000
        let targetDistance = (raw.plan_summary?.target_km ?? plannedDistanceKm(from: normalizedSessions)) * 1000
        let remainingDistance = (raw.plan_summary?.remaining_km.map { $0 * 1000 }) ?? max(targetDistance - completedDistance, 0)

        let visibleSessions = displayableSessions(normalizedSessions)

        let summary = WeeklySummary(
            weekStart: raw.week_range ?? raw.week_label ?? "",
            totalDistance: completedDistance,
            totalDuration: runTotals?.duration_sec ?? completedDuration(from: normalizedSessions),
            totalActivities: runTotals?.count ?? visibleSessions.filter(\.isCompleted).count,
            phase: raw.diagnosis?.phase_name ?? raw.diagnosis?.phase,
            phaseDescription: raw.plan_summary?.target_reason ?? raw.headline?.strippingHTML()
        )

        let progress = TrainingProgress(
            targetDistance: targetDistance,
            completedDistance: completedDistance,
            remainingDistance: remainingDistance,
            completedSessions: visibleSessions.filter(\.isCompleted).count,
            plannedSessions: visibleSessions.filter { !$0.isCompleted }.count,
            guidance: trainingGuidance(
                completedDistance: completedDistance,
                targetDistance: targetDistance,
                remainingDistance: remainingDistance,
                phase: raw.diagnosis?.phase_name ?? raw.diagnosis?.phase
            )
        )

        return (normalizedSessions, summary, progress)
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

        sessions = normalizeSessions(cached.value.sessions)
        summary = cached.value.summary
        progress = cached.value.progress
        weekDays = cached.value.weekDays
        await mergeCurrentWeekHealthData()
        rebuildWeekDays()
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

        let weekSessions = normalizeSessions(sessions)

        weekDays = (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: interval.start) ?? interval.start
            let dateKey = dateString(from: date)
            let daySessions = weekDisplaySessions(weekSessions)
                .filter { $0.date == dateKey }
                .sorted { lhs, rhs in
                    let left = lhs.startedAt ?? self.date(from: lhs.date) ?? .distantPast
                    let right = rhs.startedAt ?? self.date(from: rhs.date) ?? .distantPast
                    return left < right
                }

            return TrainingWeekDay(
                id: dateKey,
                date: date,
                weekday: formatter.string(from: date),
                title: dateTitle(for: date),
                sessions: daySessions,
                recoveryAdvice: recoveryAdvice(for: date, sessions: daySessions)
            )
        }
    }

    private func recoveryAdvice(for date: Date, sessions: [TrainingSession]) -> String {
        if sessions.isEmpty {
            return Calendar.current.isDateInToday(date)
                ? "今天没有安排跑步训练。保持轻量活动，优先恢复。"
                : "没有安排跑步训练，保持轻量活动。"
        }

        if sessions.allSatisfy(\.isRestWorkout) {
            return sessions.first?.description ?? "休息日，保持轻量活动，优先恢复。"
        }

        if let firstSession = sessions.first {
            if firstSession.isCompleted, let actualDistance = firstSession.actualDistance, actualDistance > 0, firstSession.hasPlannedWorkout {
                let planned = firstSession.plannedDistance ?? firstSession.distance
                let deltaKm = (actualDistance - planned) / 1000
                if abs(deltaKm) < 0.3 {
                    return "已完成，和计划基本匹配。今天重点补水、拉伸，后续按恢复状态推进。"
                }
                if deltaKm > 0 {
                    return "已完成，比计划多 \(String(format: "%.1f", deltaKm)) km。剩余训练不要硬补强度，优先恢复。"
                }
                return "已完成，比计划少 \(String(format: "%.1f", abs(deltaKm))) km。若身体正常，可把差额分散到后续轻松跑。"
            }

            if sessions.count > 1 {
                return "今天有 \(sessions.count) 项训练，优先按时间完成；结束后补水、拉伸并观察腿部反馈。"
            }

            return firstSession.description ?? "计划未完成。优先在本周剩余日期安排一次低强度补跑，不建议一次性堆量。"
        }

        return "没有安排跑步训练，保持轻量活动。"
    }

    private func resetPreparedExport() {
        garminExportURL = nil
        if case .succeeded = exportState {
            exportState = .idle
        }
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

        var mergedSessions = normalizeSessions(sessions)

        for workout in healthWorkouts {
            if mergedSessions.contains(where: { $0.id == workout.id }) {
                continue
            }

            if let matchIndex = matchingPlannedSessionIndex(for: workout, in: mergedSessions) {
                mergedSessions[matchIndex] = completedSession(from: mergedSessions[matchIndex], workout: workout)
            } else if !hasCompletedWorkout(on: workout.startedAt, matching: workout, in: mergedSessions) {
                mergedSessions.append(trainingSession(from: workout))
            }
        }

        mergedSessions = normalizeSessions(mergedSessions)

        if mergedSessions.map(\.id) != sessions.map(\.id) || mergedSessions.count != sessions.count {
            sessions = mergedSessions.sorted { lhs, rhs in
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
            plannedSessions: displayableSessions(sessions).filter { !$0.isCompleted }.count,
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
                totalActivities: max(summary.totalActivities, healthWorkouts.count),
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

    private func completedSession(from plan: TrainingSession, workout: TodayWorkoutSummary) -> TrainingSession {
        TrainingSession(
            id: workout.id,
            name: plan.name,
            type: plan.type,
            date: dateString(from: workout.startedAt),
            distance: workout.distanceKm.map { $0 * 1000 } ?? plan.distance,
            duration: Int(workout.durationMinutes * 60),
            averageHeartrate: plan.averageHeartrate,
            averagePace: plan.averagePace,
            description: plan.description,
            status: "completed",
            plannedDistance: plan.plannedDistance ?? plan.distance,
            plannedDuration: plan.plannedDuration ?? plan.duration,
            actualDistance: workout.distanceKm.map { $0 * 1000 },
            actualDuration: Int(workout.durationMinutes * 60),
            zone: plan.zone,
            startedAt: workout.startedAt
        )
    }

    private func matchingPlannedSessionIndex(for workout: TodayWorkoutSummary, in sessions: [TrainingSession]) -> Int? {
        let workoutDate = dateString(from: workout.startedAt)
        return sessions.firstIndex { session in
            guard session.date == workoutDate, !session.isCompleted, session.isRunningWorkout else { return false }
            let plannedDistance = session.plannedDistance ?? session.distance
            guard plannedDistance > 0, let workoutDistance = workout.distanceKm.map({ $0 * 1000 }) else { return true }
            return abs(plannedDistance - workoutDistance) <= max(1000, plannedDistance * 0.35)
        }
    }

    private func hasCompletedWorkout(on date: Date, matching workout: TodayWorkoutSummary, in sessions: [TrainingSession]) -> Bool {
        let dateKey = dateString(from: date)
        return sessions.contains { session in
            guard session.date == dateKey, session.isCompleted, session.isRunningWorkout else { return false }
            if let workoutDistance = workout.distanceKm.map({ $0 * 1000 }) {
                let comparableDistance = session.actualDistance ?? session.distance
                guard abs(comparableDistance - workoutDistance) <= max(500, workoutDistance * 0.15) else {
                    return false
                }
                return session.hasWorkoutDetailLink
            }
            return session.hasWorkoutDetailLink
        }
    }

    private func displayableSessions(_ sessions: [TrainingSession]) -> [TrainingSession] {
        sessions.filter { session in
            let planned = session.hasPlannedWorkout
            let actual = session.hasActualWorkout
            return planned || actual
        }
    }

    private func weekDisplaySessions(_ sessions: [TrainingSession]) -> [TrainingSession] {
        sessions.filter { session in
            session.isRestWorkout || session.hasPlannedWorkout || session.hasActualWorkout
        }
    }

    private func normalizeSessions(_ sessions: [TrainingSession]) -> [TrainingSession] {
        let grouped = Dictionary(grouping: sessions, by: \.date)
        return grouped.values.flatMap { normalizeDaySessions($0) }
            .sorted { lhs, rhs in
                let leftDate = lhs.startedAt ?? date(from: lhs.date) ?? .distantPast
                let rightDate = rhs.startedAt ?? date(from: rhs.date) ?? .distantPast
                return leftDate > rightDate
            }
    }

    private func normalizeDaySessions(_ daySessions: [TrainingSession]) -> [TrainingSession] {
        let restSessions = daySessions.filter(\.isRestWorkout)
        let workoutSessions = daySessions.filter { !$0.isRestWorkout }
        guard !workoutSessions.isEmpty else {
            return Array(restSessions.prefix(1))
        }

        let actualSessions = workoutSessions.filter { $0.isCompleted && $0.hasActualWorkout && $0.isRunningWorkout }
        let plannedSessions = workoutSessions.filter { $0.hasPlannedWorkout }
        let incompletePlans = workoutSessions.filter { !$0.isCompleted && $0.hasPlannedWorkout }

        var usedPlanIDs = Set<String>()
        var normalized: [TrainingSession] = []

        for cluster in actualClusters(from: actualSessions) {
            guard let actual = preferredActualSession(from: cluster) else { continue }
            let plan = matchingPlan(for: actual, from: plannedSessions, excluding: usedPlanIDs)
                ?? cluster.first(where: \.hasPlannedWorkout)
            if let plan {
                usedPlanIDs.insert(plan.id)
                normalized.append(merge(plan: plan, into: actual))
            } else {
                normalized.append(actual)
            }
        }

        let normalizedIDs = Set(normalized.map(\.id))
        for plan in incompletePlans where !usedPlanIDs.contains(plan.id) && !normalizedIDs.contains(plan.id) {
            normalized.append(plan)
        }

        if normalized.isEmpty {
            normalized = workoutSessions
        }

        return normalized
    }

    private func actualClusters(from sessions: [TrainingSession]) -> [[TrainingSession]] {
        var clusters: [[TrainingSession]] = []
        for session in sessions {
            if let index = clusters.firstIndex(where: { cluster in
                guard let representative = cluster.first else { return false }
                return sameWorkout(session, representative)
            }) {
                clusters[index].append(session)
            } else {
                clusters.append([session])
            }
        }
        return clusters
    }

    private func preferredActualSession(from sessions: [TrainingSession]) -> TrainingSession? {
        sessions.sorted { lhs, rhs in
            if lhs.hasWorkoutDetailLink != rhs.hasWorkoutDetailLink {
                return lhs.hasWorkoutDetailLink
            }
            let leftDistance = lhs.actualDistance ?? lhs.distance
            let rightDistance = rhs.actualDistance ?? rhs.distance
            if leftDistance != rightDistance {
                return leftDistance > rightDistance
            }
            return (lhs.startedAt ?? lhs.exportDate) > (rhs.startedAt ?? rhs.exportDate)
        }.first
    }

    private func matchingPlan(for actual: TrainingSession, from plans: [TrainingSession], excluding usedIDs: Set<String>) -> TrainingSession? {
        plans.first { plan in
            guard !usedIDs.contains(plan.id), plan.date == actual.date, plan.hasPlannedWorkout else { return false }
            let plannedDistance = plan.plannedDistance ?? plan.distance
            let actualDistance = actual.actualDistance ?? actual.distance
            guard plannedDistance > 0, actualDistance > 0 else { return true }
            return abs(plannedDistance - actualDistance) <= max(1000, plannedDistance * 0.35)
        }
    }

    private func sameWorkout(_ lhs: TrainingSession, _ rhs: TrainingSession) -> Bool {
        guard lhs.date == rhs.date else { return false }
        let leftDistance = lhs.actualDistance ?? lhs.distance
        let rightDistance = rhs.actualDistance ?? rhs.distance
        guard leftDistance > 0, rightDistance > 0 else { return true }
        return abs(leftDistance - rightDistance) <= max(500, max(leftDistance, rightDistance) * 0.15)
    }

    private func merge(plan: TrainingSession, into actual: TrainingSession) -> TrainingSession {
        TrainingSession(
            id: actual.id,
            name: actual.hasWorkoutDetailLink ? actual.name : plan.name,
            type: actual.type,
            date: actual.date,
            distance: actual.actualDistance ?? actual.distance,
            duration: actual.actualDuration ?? actual.duration,
            averageHeartrate: actual.averageHeartrate ?? plan.averageHeartrate,
            averagePace: actual.averagePace ?? plan.averagePace,
            description: plan.description ?? actual.description,
            status: actual.status ?? "completed",
            plannedDistance: plan.plannedDistance ?? plan.distance,
            plannedDuration: plan.plannedDuration ?? plan.duration,
            actualDistance: actual.actualDistance ?? actual.distance,
            actualDuration: actual.actualDuration ?? actual.duration,
            zone: actual.zone ?? plan.zone,
            startedAt: actual.startedAt
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
