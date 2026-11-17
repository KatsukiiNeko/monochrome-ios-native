// PlaylistStore.swift: playlists as one versioned JSON document.
import Foundation

public struct PlaylistStore: Sendable {
    /// User data, so the cap is generous but bounded.
    public static let maxBytes = 32 * 1024 * 1024

    private let file: JSONFileStore

    public init(
        fileURL: URL,
        now: @escaping @Sendable () -> Date = { .now },
        log: (@Sendable (String) -> Void)? = nil
    ) {
        self.file = JSONFileStore(
            fileURL: fileURL,
            maxBytes: Self.maxBytes,
            now: now,
            log: log
        )
    }

    /// Missing or corrupt playlists start empty; a corrupt file is quarantined.
    public func load() -> PlaylistCollection {
        file.read(PlaylistCollection.self) ?? PlaylistCollection()
    }

    public func save(_ collection: PlaylistCollection) throws {
        try file.write(collection)
    }
}
