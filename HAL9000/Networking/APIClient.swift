import Foundation

/// Async/await API client for the running coach backend.
/// Connects to the Flask app (Modal cloud or local LAN).
actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private var baseURL: URL

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)

        // Default to Modal cloud; can be switched via settings
        baseURL = URL(string: "https://example.com")!
    }

    // MARK: - Configuration

    func updateBaseURL(_ url: URL) {
        baseURL = url
    }

    // MARK: - Request

    func send<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let request = try endpoint.makeRequest(baseURL: baseURL)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.statusCode(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    func sendRaw(_ endpoint: Endpoint) async throws -> Data {
        let request = try endpoint.makeRequest(baseURL: baseURL)
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }

        return data
    }
}
