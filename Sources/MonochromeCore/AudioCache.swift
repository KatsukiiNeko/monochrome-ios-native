// AudioCache.swift: on-disk cache for progressive audio streams, keyed by track and tier.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A verified cache hit: a local file plus the metadata stored beside it.
public struct CachedAudio: Equatable, Sendable {
    public var url: URL
    public var format: AudioFormat?
    public var duration: Double?
    public var byteSize: Int

    public init(url: URL, format: AudioFormat? = nil, duration: Double? = nil, byteSize: Int = 0) {
        self.url = url
        self.format = format
        self.duration = duration
        self.byteSize = byteSize
    }
}

/// Sidecar written next to the audio file; never keyed by URL because stream URLs expire.
public struct AudioCacheEntry: Codable, Equatable, Sendable {
    public var trackID: String
    public var quality: String
    public var fileName: String
    public var format: AudioFormat?
    public var duration: Double?
    public var byteSize: Int
    public var lastUsedAt: Date

    public init(
        trackID: String,
        quality: String,
        fileName: String,
        format: AudioFormat? = nil,
        duration: Double? = nil,
        byteSize: Int,
        lastUsedAt: Date = .now
    ) {
        self.trackID = trackID
        self.quality = quality
        self.fileName = fileName
        self.format = format
        self.duration = duration
        self.byteSize = byteSize
        self.lastUsedAt = lastUsedAt
    }
}

public struct DownloadResult: Equatable, Sendable {
    public var bytesWritten: Int
    /// Content length the server stated; nil or non-positive when it stated none.
    public var expectedBytes: Int?

    public init(bytesWritten: Int, expectedBytes: Int? = nil) {
        self.bytesWritten = bytesWritten
        self.expectedBytes = expectedBytes
    }
}

public protocol FileDownloader: Sendable {
    /// Writes the response body to `destination`; caching owns the partial file.
    func download(
        from url: URL,
        to destination: URL,
        allowsExpensiveNetwork: Bool
    ) async throws -> DownloadResult
}

/// What the player needs from a cache; faked in host tests.
public protocol AudioCaching: Sendable {
    func cachedAudio(for track: Track, quality: AudioQuality?) async -> CachedAudio?
    func store(
        _ track: Track,
        quality: AudioQuality?,
        url: URL,
        contentType: String?,
        format: AudioFormat?,
        duration: Double?
    ) async
}

public enum AudioFileType {
    /// AVFoundation needs a recognizable suffix; the catalog serves no extension at all.
    public static func fileExtension(forContentType contentType: String?) -> String {
        guard let contentType else { return "audio" }
        let type = contentType
            .split(separator: ";", maxSplits: 1)
            .first.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
            .lowercased() ?? ""
        switch type {
        case "audio/flac", "audio/x-flac": return "flac"
        case "audio/mp4", "audio/x-m4a", "audio/m4a", "audio/aac", "audio/x-aac": return "m4a"
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/wav", "audio/x-wav", "audio/wave": return "wav"
        case "audio/ogg", "audio/opus": return "ogg"
        default: return "audio"
        }
    }
}

public enum CacheEligibility {
    /// Only single-file progressive sources are cached; playlists and encrypted
    /// sources would need a manifest the cache cannot verify.
    public static func isCacheable(
        url: URL,
        contentType: String?,
        isEncrypted: Bool = false
    ) -> Bool {
        guard !isEncrypted else { return false }
        let ext = url.pathExtension.lowercased()
        if ext == "m3u8" || ext == "mpd" { return false }
        let type = (contentType ?? "").lowercased()
        if type.contains("mpegurl") || type.contains("dash") { return false }
        return true
    }
}

/// LRU cache of complete audio files with a sidecar per entry.
public actor AudioCache: AudioCaching {
    public static let defaultSizeLimitBytes = 500 * 1024 * 1024
    public static let minimumFreeSpaceBytes = 200 * 1024 * 1024

    private let directory: URL
    private let sizeLimitBytes: Int
    private let minimumFreeSpaceBytes: Int
    private let downloader: any FileDownloader
    private let allowsExpensiveNetwork: @Sendable () -> Bool
    private let log: @Sendable (String) -> Void
    private var inFlight: [String: Task<Void, Never>] = [:]

    public init(
        directory: URL,
        downloader: any FileDownloader,
        sizeLimitBytes: Int = AudioCache.defaultSizeLimitBytes,
        minimumFreeSpaceBytes: Int = AudioCache.minimumFreeSpaceBytes,
        allowsExpensiveNetwork: @escaping @Sendable () -> Bool = { false },
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.directory = directory
        self.downloader = downloader
        self.sizeLimitBytes = sizeLimitBytes
        self.minimumFreeSpaceBytes = minimumFreeSpaceBytes
        self.allowsExpensiveNetwork = allowsExpensiveNetwork
        self.log = log
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Self.removePartials(in: directory)
    }

    // MARK: - Lookup

    public func cachedAudio(for track: Track, quality: AudioQuality?) -> CachedAudio? {
        let name = Self.storageBaseName(track: track, quality: quality)
        guard var entry = Self.readEntry(named: name, in: directory) else {
            log("cache miss track=\(track.id) quality=\(Self.qualityName(quality))")
            return nil
        }
        let fileURL = directory.appendingPathComponent(entry.fileName)
        guard let size = Self.fileSize(fileURL), size == entry.byteSize, size > 0 else {
            // The system may purge Caches; a missing or short file is simply a miss.
            removeFiles(named: name, entry: entry)
            log("cache miss track=\(track.id) quality=\(Self.qualityName(quality)) reason=incomplete")
            return nil
        }
        entry.lastUsedAt = .now
        Self.write(entry: entry, named: name, in: directory)
        log("cache hit track=\(track.id) quality=\(Self.qualityName(quality)) bytes=\(size)")
        return CachedAudio(url: fileURL, format: entry.format, duration: entry.duration, byteSize: size)
    }

    // MARK: - Store

    public func store(
        _ track: Track,
        quality: AudioQuality?,
        url: URL,
        contentType: String?,
        format: AudioFormat?,
        duration: Double?
    ) async {
        guard track.isStreaming else { return }
        guard CacheEligibility.isCacheable(url: url, contentType: contentType) else {
            log("cache skip track=\(track.id) reason=unsupported-source")
            return
        }
        let name = Self.storageBaseName(track: track, quality: quality)
        if let existing = inFlight[name] {
            // Two requests for the same key share one download.
            await existing.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performStore(
                track: track,
                quality: quality,
                url: url,
                contentType: contentType,
                format: format,
                duration: duration,
                name: name
            )
        }
        inFlight[name] = task
        await task.value
        inFlight[name] = nil
    }

    private func performStore(
        track: Track,
        quality: AudioQuality?,
        url: URL,
        contentType: String?,
        format: AudioFormat?,
        duration: Double?,
        name: String
    ) async {
        guard hasFreeSpace() else {
            log("cache skip track=\(track.id) reason=low-disk")
            return
        }
        let ext = AudioFileType.fileExtension(forContentType: contentType)
        let fileName = "\(name).\(ext)"
        let partial = directory.appendingPathComponent("\(fileName).partial")
        try? FileManager.default.removeItem(at: partial)
        do {
            let result = try await downloader.download(
                from: url,
                to: partial,
                allowsExpensiveNetwork: allowsExpensiveNetwork()
            )
            guard result.bytesWritten > 0 else {
                throw CacheError.emptyDownload
            }
            if let expected = result.expectedBytes, expected > 0, expected != result.bytesWritten {
                throw CacheError.sizeMismatch(expected: expected, actual: result.bytesWritten)
            }
            let finalURL = directory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: finalURL)
            try FileManager.default.moveItem(at: partial, to: finalURL)
            let entry = AudioCacheEntry(
                trackID: track.id,
                quality: Self.qualityName(quality),
                fileName: fileName,
                format: format,
                duration: duration,
                byteSize: result.bytesWritten
            )
            Self.write(entry: entry, named: name, in: directory)
            log("cache store track=\(track.id) quality=\(Self.qualityName(quality)) bytes=\(result.bytesWritten)")
            evictIfNeeded()
        } catch {
            try? FileManager.default.removeItem(at: partial)
            log("cache store failed track=\(track.id) reason=\(error.localizedDescription)")
        }
    }

    // MARK: - Maintenance

    public func sizeBytes() -> Int {
        Self.entries(in: directory).reduce(0) { $0 + $1.byteSize }
    }

    public func clear() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        log("cache clear")
    }

    public func purgePartials() {
        Self.removePartials(in: directory)
    }

    private func evictIfNeeded() {
        var entries = Self.entries(in: directory).sorted { $0.lastUsedAt < $1.lastUsedAt }
        var total = entries.reduce(0) { $0 + $1.byteSize }
        while total > sizeLimitBytes, !entries.isEmpty {
            let oldest = entries.removeFirst()
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(oldest.fileName))
            let name = Self.storageBaseName(trackID: oldest.trackID, qualityName: oldest.quality)
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(name).json"))
            total -= oldest.byteSize
            log("cache evict track=\(oldest.trackID) bytes=\(oldest.byteSize)")
        }
    }

    private func hasFreeSpace() -> Bool {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: directory.path),
              let free = attributes[.systemFreeSize] as? NSNumber else { return true }
        return free.intValue > minimumFreeSpaceBytes
    }

    // MARK: - Files

    private func removeFiles(named name: String, entry: AudioCacheEntry) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.fileName))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(name).json"))
    }

    private static func qualityName(_ quality: AudioQuality?) -> String {
        quality?.rawValue.lowercased() ?? "default"
    }

    private static func storageBaseName(track: Track, quality: AudioQuality?) -> String {
        storageBaseName(trackID: track.id, qualityName: qualityName(quality))
    }

    private static func storageBaseName(trackID: String, qualityName: String) -> String {
        let safe = trackID.map { character in
            character.isLetter || character.isNumber ? character : "_"
        }
        return "\(String(safe).prefix(80))-\(qualityName)"
    }

    private static func readEntry(named name: String, in directory: URL) -> AudioCacheEntry? {
        let url = directory.appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AudioCacheEntry.self, from: data)
    }

    private static func write(entry: AudioCacheEntry, named name: String, in directory: URL) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: directory.appendingPathComponent("\(name).json"), options: .atomic)
    }

    private static func entries(in directory: URL) -> [AudioCacheEntry] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(AudioCacheEntry.self, from: data)
        }
    }

    private static func fileSize(_ url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return nil }
        return size.intValue
    }

    private static func removePartials(in directory: URL) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.pathExtension == "partial" {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

public enum CacheError: LocalizedError, Equatable {
    case emptyDownload
    case sizeMismatch(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyDownload: "The downloaded file was empty."
        case .sizeMismatch(let expected, let actual):
            "The downloaded file had \(actual) bytes instead of \(expected)."
        }
    }
}
