import Foundation
import HealthKit
import WorkoutKit

enum TrainingExportError: LocalizedError {
    case noExportableWorkouts
    case workoutSchedulingUnsupported
    case workoutSchedulingDenied
    case invalidGarminFile

    var errorDescription: String? {
        switch self {
        case .noExportableWorkouts:
            return "本周没有可导出的跑步训练。"
        case .workoutSchedulingUnsupported:
            return "当前设备不支持同步训练到 Apple Watch。"
        case .workoutSchedulingDenied:
            return "没有 Apple Watch 训练计划授权，请在系统设置中允许。"
        case .invalidGarminFile:
            return "无法生成 Garmin 训练文件。"
        }
    }
}

struct TrainingExportResult: Equatable {
    let count: Int
    let message: String
}

struct TrainingExportService {
    func scheduleOnAppleWatch(_ sessions: [TrainingSession]) async throws -> TrainingExportResult {
        let workouts = exportableSessions(from: sessions)
        guard !workouts.isEmpty else { throw TrainingExportError.noExportableWorkouts }
        guard WorkoutScheduler.isSupported else { throw TrainingExportError.workoutSchedulingUnsupported }

        let scheduler = WorkoutScheduler.shared
        let authorization = await scheduler.authorizationState
        let finalAuthorization: WorkoutScheduler.AuthorizationState

        if authorization == .notDetermined {
            finalAuthorization = await scheduler.requestAuthorization()
        } else {
            finalAuthorization = authorization
        }

        guard finalAuthorization == .authorized else { throw TrainingExportError.workoutSchedulingDenied }

        for session in workouts {
            await scheduler.schedule(workoutPlan(for: session), at: dateComponents(for: session))
        }

        return TrainingExportResult(
            count: workouts.count,
            message: "已同步 \(workouts.count) 节课到 Apple Watch 体能训练。"
        )
    }

    func makeGarminTCXFile(from sessions: [TrainingSession]) throws -> URL {
        let workouts = exportableSessions(from: sessions)
        guard !workouts.isEmpty else { throw TrainingExportError.noExportableWorkouts }

        let data = garminTCX(for: workouts)
        guard let encoded = data.data(using: .utf8) else { throw TrainingExportError.invalidGarminFile }

        let fileName = "HAL9000-Training-\(fileStamp()).tcx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try encoded.write(to: url, options: .atomic)
        return url
    }

    private func exportableSessions(from sessions: [TrainingSession]) -> [TrainingSession] {
        sessions
            .filter { !$0.isCompleted }
            .filter { $0.isRunningWorkout }
            .filter { $0.exportDistanceMeters > 0 || $0.exportDurationSeconds > 0 }
            .sorted { $0.date < $1.date }
    }

    private func workoutPlan(for session: TrainingSession) -> WorkoutPlan {
        let step = WorkoutStep(
            goal: workoutGoal(for: session),
            alert: heartRateAlert(for: session)
        )

        let workout = CustomWorkout(
            activity: .running,
            location: .unknown,
            displayName: session.exportTitle,
            blocks: [
                IntervalBlock(
                    steps: [IntervalStep(.work, step: step)],
                    iterations: 1
                )
            ]
        )

        return WorkoutPlan(.custom(workout), id: stableWorkoutID(for: session))
    }

    private func workoutGoal(for session: TrainingSession) -> WorkoutGoal {
        if session.exportDistanceMeters > 0 {
            return .distance(session.exportDistanceMeters / 1000, .kilometers)
        }

        if session.exportDurationSeconds > 0 {
            return .time(Double(session.exportDurationSeconds) / 60, .minutes)
        }

        return .open
    }

    private func heartRateAlert(for session: TrainingSession) -> (any WorkoutAlert)? {
        guard let zone = session.zoneNumber else { return nil }
        return HeartRateZoneAlert(zone: zone)
    }

    private func dateComponents(for session: TrainingSession) -> DateComponents {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: session.exportDate)
        components.hour = 7
        components.minute = 0
        return components
    }

    private func garminTCX(for sessions: [TrainingSession]) -> String {
        let workouts = sessions.map { session in
            let duration = garminDuration(for: session)
            return [
                "  <Workout Sport=\"Running\">",
                "    <Name>\(xmlEscape(session.exportTitle))</Name>",
                "    <Step xsi:type=\"Step_t\">",
                "      <StepId>1</StepId>",
                "      <Name>\(xmlEscape(session.exportTitle))</Name>",
                duration,
                "      <Intensity>\(session.garminIntensity)</Intensity>",
                "      <Target xsi:type=\"HeartRateZone_t\">",
                "        <Number>\(session.zoneNumber ?? 2)</Number>",
                "      </Target>",
                "    </Step>",
                "  </Workout>"
            ].joined(separator: "\n")
        }
        .joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase
          xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd">
          <Workouts>
        \(workouts)
          </Workouts>
          <Author xsi:type="Application_t">
            <Name>HAL9000 Runner Coach</Name>
            <Build>
              <Version>
                <VersionMajor>1</VersionMajor>
                <VersionMinor>0</VersionMinor>
                <BuildMajor>1</BuildMajor>
                <BuildMinor>0</BuildMinor>
              </Version>
            </Build>
            <LangID>zh</LangID>
            <PartNumber>HAL9000</PartNumber>
          </Author>
        </TrainingCenterDatabase>
        """
    }

    private func garminDuration(for session: TrainingSession) -> String {
        if session.exportDistanceMeters > 0 {
            return [
                "      <Duration xsi:type=\"Distance_t\">",
                "        <Meters>\(String(format: "%.0f", session.exportDistanceMeters))</Meters>",
                "      </Duration>"
            ].joined(separator: "\n")
        }

        return [
            "      <Duration xsi:type=\"Time_t\">",
            "        <Seconds>\(max(session.exportDurationSeconds, 1))</Seconds>",
            "      </Duration>"
        ].joined(separator: "\n")
    }

    private func fileStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    private func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func stableWorkoutID(for session: TrainingSession) -> UUID {
        let key = "\(session.id)|\(session.date)|\(session.exportTitle)"
        let keyBytes = Array(key.utf8)
        var hash: UInt64 = 0xcbf29ce484222325

        for byte in keyBytes {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }

        var bytes = Array(repeating: UInt8(0), count: 16)
        for index in 0..<bytes.count {
            let shift = UInt64((index % 8) * 8)
            bytes[index] = UInt8((hash >> shift) & 0xff)
        }

        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80

        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let part1 = String(hex.prefix(8))
        let part2Start = hex.index(hex.startIndex, offsetBy: 8)
        let part3Start = hex.index(hex.startIndex, offsetBy: 12)
        let part4Start = hex.index(hex.startIndex, offsetBy: 16)
        let part5Start = hex.index(hex.startIndex, offsetBy: 20)
        let part2 = String(hex[part2Start..<part3Start])
        let part3 = String(hex[part3Start..<part4Start])
        let part4 = String(hex[part4Start..<part5Start])
        let part5 = String(hex[part5Start..<hex.endIndex])
        let uuidString = "\(part1)-\(part2)-\(part3)-\(part4)-\(part5)"

        return UUID(uuidString: uuidString) ?? UUID()
    }
}
