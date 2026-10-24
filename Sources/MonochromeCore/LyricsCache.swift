// LyricsCache.swift: bounded on-disk lyrics cache with positive and negative TTLs.
import Foundation

public actor LyricsCache {
    public static let positiveLifetime: TimeInterval = 30 * 24 * 60 * 60
    /// A missing song is remembered for a week so every sheet open is not a new query.
    public static let negativeLifetime: TimeInterval = 7 * 24 * 60 * 60

    private let directory: URL
    private let maxEntries: Int

    public init(directory: URL, maxEntries: Int = 500) {
        self.directory = directory
        self.maxEntries = max(maxEntries, 1)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func result(
        for query: LyricsQuery,
        provider: String,
        now: Date,
        allowExpired: Bool = false
    ) -> LyricsResult? {
        let file = fileURL(for: query, provider: provider)
        guard let data = try? Data(contentsOf: file),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.provider == provider
        else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }

        let lifetime = record.result.isNotFound
            ? Self.negativeLifetime
            : Self.positiveLifetime
        let age = now.timeIntervalSince(record.storedAt)
        let isFresh = age >= 0 && age <= lifetime
        // Expired entries stay on disk so an offline load can still show them;
        // the size bound eventually removes them.
        guard isFresh || allowExpired else { return nil }
        if isFresh {
            // Reading a fresh entry marks it as recently used for the size bound.
            try? FileManager.default.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: file.path
            )
        }
        return record.result
    }

    public func store(
        _ result: LyricsResult,
        for query: LyricsQuery,
        provider: String,
        now: Date
    ) {
        let file = fileURL(for: query, provider: provider)
        let record = Record(
            provider: provider,
            trackID: query.trackID,
            source: result.source,
            storedAt: now,
            result: result
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        do {
            try data.write(to: file, options: .atomic)
            try? FileManager.default.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: file.path
            )
        } catch {
            return
        }
        trim(keeping: maxEntries)
    }

    public func remove(for query: LyricsQuery, provider: String) {
        try? FileManager.default.removeItem(at: fileURL(for: query, provider: provider))
    }

    public func count() -> Int {
        recordFiles().count
    }

    // MARK: - Files

    /// Stable provider + track id key; the hash prevents sanitized ids colliding.
    public static func key(provider: String, trackID: String) -> String {
        let raw = "\(provider)|\(trackID)"
        let prefixScalars = raw.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        let prefix = String(String.UnicodeScalarView(prefixScalars.prefix(40)))
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in raw.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let name = prefix.isEmpty ? "lyrics" : prefix
        return "\(name)-\(String(hash, radix: 16))"
    }

    private func fileURL(for query: LyricsQuery, provider: String) -> URL {
        directory
            .appendingPathComponent(Self.key(provider: provider, trackID: query.trackID))
            .appendingPathExtension("json")
    }

    private func recordFiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { $0.pathExtension == "json" }
    }

    private func trim(keeping limit: Int) {
        let files = recordFiles()
        guard files.count > limit else { return }
        let oldestFirst = files.sorted { lhs, rhs in
            modificationDate(lhs) < modificationDate(rhs)
        }
        for file in oldestFirst.prefix(files.count - limit) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func modificationDate(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    private struct Record: Codable {
        var provider: String
        var trackID: String
        var source: String
        var storedAt: Date
        var result: LyricsResult
    }
}
