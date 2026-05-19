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
        if useLocalServer {
            return URL(string: "http://\(localIP):\(localPort)")!
        }
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private init() {
        self.useLocalServer = UserDefaults.standard.bool(forKey: "useLocalServer")
        self.localIP = UserDefaults.standard.string(forKey: "localIP") ?? "127.0.0.1"
        self.localPort = UserDefaults.standard.string(forKey: "localPort") ?? "5051"
        self.serverURL = UserDefaults.standard.string(forKey: "serverURL")
            ?? ""
    }
}
