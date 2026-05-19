import Foundation

// MARK: - API Error

enum APIError: LocalizedError {
    case invalidURL
    case missingServerURL
    case invalidResponse
    case statusCode(Int)
    case decodingFailed(Error)
    case networkError(Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:        return "无效的 URL"
        case .missingServerURL:  return "请先配置后端服务地址"
        case .invalidResponse:   return "服务器响应异常"
        case .statusCode(let c): return "服务器错误 (\(c))"
        case .decodingFailed:    return "数据解析失败"
        case .networkError(let e): return e.localizedDescription
        case .unauthorized:      return "认证失败，请重新登录"
        }
    }
}

// MARK: - HTTP Method

enum HTTPMethod: String {
    case get  = "GET"
    case post = "POST"
}

// MARK: - Endpoint

struct Endpoint {
    let path: String
    let method: HTTPMethod
    let queryItems: [URLQueryItem]?
    let body: Data?

    init(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem]? = nil,
        body: Data? = nil
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.body = body
    }

    func makeRequest(baseURL: URL) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }

        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        return request
    }
}
