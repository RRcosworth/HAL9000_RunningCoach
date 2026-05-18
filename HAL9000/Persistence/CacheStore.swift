import Foundation

/// Simple in-memory key-value cache with TTL.
actor CacheStore {
    static let shared = CacheStore()

    private var storage: [String: CacheEntry] = [:]
    private let defaultTTL: TimeInterval = 300 // 5 min

    private struct CacheEntry {
        let value: Data
        let expiresAt: Date
    }

    func get<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let entry = storage[key], entry.expiresAt > Date() else {
            storage[key] = nil
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: entry.value)
    }

    func set<T: Encodable>(_ value: T, for key: String, ttl: TimeInterval? = nil) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        storage[key] = CacheEntry(
            value: data,
            expiresAt: Date().addingTimeInterval(ttl ?? defaultTTL)
        )
    }

    func remove(_ key: String) {
        storage[key] = nil
    }

    func removeAll() {
        storage.removeAll()
    }
}
