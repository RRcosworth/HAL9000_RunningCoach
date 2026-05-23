import Foundation

/// Simple user preferences store using UserDefaults.
@MainActor
final class UserSessionStore: ObservableObject {
    static let shared = UserSessionStore()

    @Published var useLocalServer: Bool {
        didSet { UserDefaults.standard.set(useLocalServer, forKey: "useLocalServer") }
    }

    @Published var localIP: String {
        didSet { UserDefaults.standard.set(localIP, forKey: "localIP") }
    }

    @Published var localPort: String {
        didSet { UserDefaults.standard.set(localPort, forKey: "localPort") }
    }

    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }

    var resolvedBaseURL: URL? {
        let shouldUseLocalServer = useLocalServer
            || (serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && LocalConfiguration.useLocalServer)

        if shouldUseLocalServer {
            let bundledHost = LocalConfiguration.localServerHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let bundledPort = LocalConfiguration.localServerPort.trimmingCharacters(in: .whitespacesAndNewlines)
            let host = LocalConfiguration.useLocalServer && !bundledHost.isEmpty
                ? bundledHost
                : localIP.trimmingCharacters(in: .whitespacesAndNewlines)
            let port = LocalConfiguration.useLocalServer && !bundledPort.isEmpty
                ? bundledPort
                : localPort.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !host.isEmpty, !port.isEmpty else { return nil }
            return URL(string: "http://\(host):\(port)")
        }
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private init() {
        let defaults = UserDefaults.standard

        self.useLocalServer = defaults.object(forKey: "useLocalServer") as? Bool
            ?? LocalConfiguration.useLocalServer
        self.localIP = defaults.string(forKey: "localIP")
            ?? LocalConfiguration.localServerHost
        self.localPort = defaults.string(forKey: "localPort")
            ?? LocalConfiguration.localServerPort

        let storedServerURL = defaults.string(forKey: "serverURL")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.serverURL = storedServerURL?.isEmpty == false
            ? storedServerURL ?? ""
            : LocalConfiguration.backendBaseURL
    }
}
