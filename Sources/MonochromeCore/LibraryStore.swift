// LibraryStore.swift: reads and writes the track list as one JSON file.
import Foundation

public struct LibraryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> [Track] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([Track].self, from: data)
    }

    public func save(_ tracks: [Track]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Atomic write so a crash mid-save cannot leave a truncated library.
        try encoder.encode(tracks).write(to: fileURL, options: .atomic)
    }
}
