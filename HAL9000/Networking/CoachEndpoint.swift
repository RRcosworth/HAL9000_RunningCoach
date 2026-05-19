import Foundation

extension Endpoint {
    static func coachChat(_ request: CoachChatRequest, mock: Bool = false) throws -> Endpoint {
        let body = try JSONEncoder.coach.encode(request)
        return Endpoint(
            path: "api/coach/chat",
            method: .post,
            queryItems: mock ? [URLQueryItem(name: "mock", value: "true")] : nil,
            body: body
        )
    }
}

extension JSONEncoder {
    static var coach: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var coach: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
