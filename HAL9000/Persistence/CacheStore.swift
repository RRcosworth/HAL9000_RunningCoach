import Foundation

/// In-memory cache backed by a small JSON disk store.
actor CacheStore {
    static let shared = CacheStore()

    private var storage: [String: CacheEntry] = [:]
    private let defaultTTL: TimeInterval = 300 // 5 min
    private let directory: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("HAL9000Cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private struct CacheEntry: Codable {
        let value: Data
        let expiresAt: Date
    }

    func get<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let cached: CachedValue<T> = getIncludingExpired(key, as: type),
              !cached.isExpired
        else { return nil }

        return cached.value
    }

    func getIncludingExpired<T: Decodable>(_ key: String, as type: T.Type) -> CachedValue<T>? {
        guard let entry = entry(for: key) else { return nil }
        guard let value = try? JSONDecoder().decode(T.self, from: entry.value) else { return nil }
        return CachedValue(value: value, isExpired: entry.expiresAt <= Date(), expiresAt: entry.expiresAt)
    }

    func set<T: Encodable>(_ value: T, for key: String, ttl: TimeInterval? = nil) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let entry = CacheEntry(
            value: data,
            expiresAt: Date().addingTimeInterval(ttl ?? defaultTTL)
        )
        storage[key] = entry
        write(entry, for: key)
    }

    func remove(_ key: String) {
        storage[key] = nil
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    func removeAll() {
        storage.removeAll()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func entry(for key: String) -> CacheEntry? {
        if let entry = storage[key] { return entry }
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data)
        else { return nil }
        storage[key] = entry
        return entry
    }

    private func write(_ entry: CacheEntry, for key: String) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    private func fileURL(for key: String) -> URL {
        let safeKey = key
            .replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
        return directory.appendingPathComponent("\(safeKey).json")
    }
}

struct CachedValue<T> {
    let value: T
    let isExpired: Bool
    let expiresAt: Date
}
