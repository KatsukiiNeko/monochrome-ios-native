// JSONFileStore.swift: one versioned, atomic JSON file with corruption quarantine and a size cap.
import Foundation

public enum JSONFileStoreError: LocalizedError, Equatable {
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .tooLarge: "The saved data has reached its size limit."
        }
    }
}

/// A small file seam: callers own the schema, the store owns durability.
/// A file that cannot be decoded or exceeds the cap is renamed aside, never deleted.
public struct JSONFileStore: Sendable {
    public let fileURL: URL
    public let maxBytes: Int
    private let now: @Sendable () -> Date
    private let log: (@Sendable (String) -> Void)?

    public init(
        fileURL: URL,
        maxBytes: Int,
        now: @escaping @Sendable () -> Date = { .now },
        log: (@Sendable (String) -> Void)? = nil
    ) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        self.now = now
        self.log = log
    }

    /// Returns nil when the file is missing, unreadable, corrupt or oversized.
    /// A corrupt file is moved aside so the next save starts from a clean state.
    public func read<T: Decodable>(_ type: T.Type) -> T? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else {
            quarantine(reason: "unreadable")
            return nil
        }
        guard data.count <= maxBytes else {
            quarantine(reason: "oversized")
            return nil
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            quarantine(reason: "corrupt")
            return nil
        }
    }

    public func write<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard data.count <= maxBytes else { throw JSONFileStoreError.tooLarge }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Atomic write: a crash mid-save leaves the previous file intact.
        try data.write(to: fileURL, options: .atomic)
    }

    private func quarantine(reason: String) {
        let stamp = Int(now().timeIntervalSince1970)
        var destination = fileURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp).json")
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = fileURL
                .deletingPathExtension()
                .appendingPathExtension("corrupt-\(stamp)-\(UUID().uuidString).json")
        }
        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
            log?("json quarantine reason=\(reason) file=\(fileURL.lastPathComponent)")
        } catch {
            log?("json quarantine failed reason=\(reason)")
        }
    }
}
