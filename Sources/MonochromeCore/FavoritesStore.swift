// FavoritesStore.swift: the set of favorite track ids, persisted as JSON.
import Foundation

public struct FavoritesStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return Set(try JSONDecoder().decode([String].self, from: data))
    }

    public func save(_ ids: Set<String>) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(ids.sorted())
        try data.write(to: fileURL, options: .atomic)
    }
}
