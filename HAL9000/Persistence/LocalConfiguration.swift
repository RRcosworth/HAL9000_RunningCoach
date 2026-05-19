import Foundation

enum LocalConfiguration {
    static var profileDisplayName: String {
        infoString("HAL9000ProfileDisplayName", fallback: "Runner")
    }

    static var backendBaseURL: String {
        infoString("HAL9000BackendBaseURL")
    }

    static var useLocalServer: Bool {
        let value = infoString("HAL9000UseLocalServer").lowercased()
        return value == "yes" || value == "true" || value == "1"
    }

    static var localServerHost: String {
        infoString("HAL9000LocalServerHost", fallback: "127.0.0.1")
    }

    static var localServerPort: String {
        infoString("HAL9000LocalServerPort", fallback: "5051")
    }

    private static func infoString(_ key: String, fallback: String = "") -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return fallback
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else {
            return fallback
        }

        return trimmed
    }
}
