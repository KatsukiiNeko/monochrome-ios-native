// CatalogResponseCache.swift: cached catalog responses with per-kind TTL and LRU eviction.
import Foundation

public struct CachedCatalogResponse: Sendable, Equatable {
    public let data: Data
    public let statusCode: Int
    public let storedAt: Date

    public init(data: Data, statusCode: Int, storedAt: Date) {
        self.data = data
        self.statusCode = statusCode
        self.storedAt = storedAt
    }
}

/// One JSON index plus one file per response. The index is the source of truth:
/// response files the index does not name are deleted on load, and an unreadable
/// index is quarantined by `JSONFileStore` so the cache simply starts empty.
public actor CatalogResponseCache {
    public static let defaultCapacityBytes = 50 * 1024 * 1024
    static let indexMaxBytes = 8 * 1024 * 1024

    private struct Entry: Codable {
        var key: String
        var kind: String
        var fileName: String
        var byteSize: Int
        var statusCode: Int
        var storedAt: Date
        var lastAccess: Date
    }

    private struct Index: Codable {
        var schemaVersion: Int
        var entries: [Entry]
    }

    private let directory: URL
    private let capacityBytes: Int
    private let now: @Sendable () -> Date
    private let log: (@Sendable (String) -> Void)?
    private let indexStore: JSONFileStore
    private var entries: [String: Entry]

    public init(
        directory: URL,
        capacityBytes: Int = CatalogResponseCache.defaultCapacityBytes,
        now: @escaping @Sendable () -> Date = { .now },
        log: (@Sendable (String) -> Void)? = nil
    ) {
        self.directory = directory
        self.capacityBytes = max(capacityBytes, 0)
        self.now = now
        self.log = log
        self.indexStore = JSONFileStore(
            fileURL: directory.appendingPathComponent("index.json"),
            maxBytes: Self.indexMaxBytes,
            now: now,
            log: log
        )

        // Keep only entries whose response file still exists, then drop orphans.
        var restored: [String: Entry] = [:]
        for entry in indexStore.read(Index.self)?.entries ?? [] {
            let file = directory.appendingPathComponent(entry.fileName)
            if FileManager.default.fileExists(atPath: file.path) {
                restored[entry.key] = entry
            }
        }
        self.entries = restored
        let referenced = Set(restored.values.map(\.fileName))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasSuffix(".bin") && !referenced.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    // MARK: - Reads

    /// Returns the stored response and whether it is still inside its TTL. A stale
    /// entry is still returned so the caller can serve it while revalidating.
    public func entry(for key: CatalogRequestKey) -> (response: CachedCatalogResponse, isFresh: Bool)? {
        guard var entry = entries[key.value] else { return nil }
        let file = directory.appendingPathComponent(entry.fileName)
        guard let data = try? Data(contentsOf: file) else {
            entries[key.value] = nil
            persist()
            log?("catalog cache dropped reason=missing-file")
            return nil
        }
        let stamp = now()
        entry.lastAccess = stamp
        entries[key.value] = entry
        persist()
        let age = stamp.timeIntervalSince(entry.storedAt)
        return (
            CachedCatalogResponse(data: data, statusCode: entry.statusCode, storedAt: entry.storedAt),
            age < key.kind.timeToLive
        )
    }

    public func totalBytes() -> Int {
        entries.values.reduce(0) { $0 + $1.byteSize }
    }

    public func entryCount() -> Int {
        entries.count
    }

    /// Test and diagnostics seam: the stored time of one entry.
    public func storedAt(for key: CatalogRequestKey) -> Date? {
        entries[key.value]?.storedAt
    }

    // MARK: - Writes

    /// A response larger than the whole budget is rejected instead of evicting
    /// everything else to hold it.
    public func store(data: Data, statusCode: Int, for key: CatalogRequestKey) {
        guard data.count <= capacityBytes else {
            log?("catalog cache reject reason=oversized")
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileName = Self.fileName(for: key.value)
            try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
            let stamp = now()
            entries[key.value] = Entry(
                key: key.value,
                kind: key.kind.rawValue,
                fileName: fileName,
                byteSize: data.count,
                statusCode: statusCode,
                storedAt: stamp,
                lastAccess: stamp
            )
            evictOverBudget(protecting: key.value)
            persist()
        } catch {
            log?("catalog cache write failed reason=\(error.localizedDescription)")
        }
    }

    public func removeAll() {
        entries = [:]
        persist()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where file.hasSuffix(".bin") {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    // MARK: - Housekeeping

    /// Evicts least-recently-used entries until the cache fits its budget.
    private func evictOverBudget(protecting key: String) {
        while totalBytes() > capacityBytes {
            let victim = entries.values
                .filter { $0.key != key }
                .min { $0.lastAccess < $1.lastAccess }
            guard let victim else { break }
            entries[victim.key] = nil
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(victim.fileName))
            log?("catalog cache evict key=\(victim.key)")
        }
    }

    private func persist() {
        let index = Index(schemaVersion: 1, entries: entries.values.sorted { $0.key < $1.key })
        try? indexStore.write(index)
    }

    /// A stable file name that survives launches, unlike `Hasher`.
    static func fileName(for key: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016lx.bin", hash)
    }
}
