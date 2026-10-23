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
    /// Display metadata; older sidecars decode these as nil.
    public var title: String?
    public var artist: String?
    public var artworkURL: URL?

    public init(
        trackID: String,
        quality: String,
        fileName: String,
        format: AudioFormat? = nil,
        duration: Double? = nil,
        byteSize: Int,
        lastUsedAt: Date = .now,
        title: String? = nil,
        artist: String? = nil,
        artworkURL: URL? = nil
    ) {
        self.trackID = trackID
        self.quality = quality
        self.fileName = fileName
        self.format = format
        self.duration = duration
        self.byteSize = byteSize
        self.lastUsedAt = lastUsedAt
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
    }
}

/// One row for the Settings cache list.
public struct CachedTrackSummary: Identifiable, Equatable, Sendable {
    public var id: String { fileName }
    public var trackID: String
    public var quality: String
    public var fileName: String
    public var title: String?
    public var artist: String?
    public var artworkURL: URL?
    public var byteSize: Int
    public var lastUsedAt: Date

    public init(
        trackID: String,
        quality: String,
        fileName: String,
        title: String? = nil,
        artist: String? = nil,
        artworkURL: URL? = nil,
        byteSize: Int,
        lastUsedAt: Date
    ) {
        self.trackID = trackID
        self.quality = quality
        self.fileName = fileName
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
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
    /// Cancels a background download that belongs to a track the user left.
    func cancelDownload(for track: Track, quality: AudioQuality?, reason: String) async
}

public extension AudioCaching {
    /// A cache that does not download in the background has nothing to cancel.
    func cancelDownload(for track: Track, quality: AudioQuality?, reason: String) async {}
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
    private struct InFlight {
        let id: UUID
        let task: Task<Void, Never>
    }
    private struct Waiter {
        let id: UUID
        let name: String
        let continuation: CheckedContinuation<Bool, Never>
    }
    private var inFlight: [String: InFlight] = [:]
    /// Two downloads may run at once so a new track is not stuck behind a long one.
    private var activeTokens: Set<UUID> = []
    private var waiters: [Waiter] = []
    private var cancelReasons: [String: String] = [:]
    private static let maxConcurrentDownloads = 2

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
        // Fill metadata for entries written before the Settings list existed.
        if entry.title == nil { entry.title = track.title }
        if entry.artist == nil { entry.artist = track.displayArtist }
        if entry.artworkURL == nil { entry.artworkURL = track.artworkURL }
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
        let name = Self.storageBaseName(track: track, quality: quality)
        guard CacheEligibility.isCacheable(url: url, contentType: contentType) else {
            log("cache skip key=\(name) reason=uncacheable format=\(contentType ?? "unknown")")
            return
        }
        if let existing = inFlight[name] {
            // Two requests for the same key share one download.
            await existing.task.value
            return
        }
        if Self.hasCompleteEntry(named: name, in: directory) {
            log("cache skip key=\(name) reason=already-cached")
            return
        }
        let id = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performStore(
                track: track,
                quality: quality,
                url: url,
                contentType: contentType,
                format: format,
                duration: duration,
                name: name,
                id: id
            )
        }
        inFlight[name] = InFlight(id: id, task: task)
        await task.value
        if inFlight[name]?.id == id {
            inFlight[name] = nil
        }
    }

    private func performStore(
        track: Track,
        quality: AudioQuality?,
        url: URL,
        contentType: String?,
        format: AudioFormat?,
        duration: Double?,
        name: String,
        id: UUID
    ) async {
        guard !Task.isCancelled else {
            log("cache cancel key=\(name) reason=\(cancelReason(for: name))")
            return
        }
        guard let token = await acquireSlot(id: id, name: name) else { return }
        defer { releaseSlot(token: token) }
        guard !Task.isCancelled else {
            log("cache cancel key=\(name) reason=\(cancelReason(for: name))")
            return
        }
        ensureDirectory()
        guard hasFreeSpace() else {
            log("cache skip key=\(name) reason=low-space")
            return
        }
        let ext = AudioFileType.fileExtension(forContentType: contentType)
        let fileName = "\(name).\(ext)"
        // Unique per attempt: a cancelled download must never delete a newer partial.
        let partial = directory.appendingPathComponent("\(fileName).\(id.uuidString).partial")
        try? FileManager.default.removeItem(at: partial)
        log("cache download start key=\(name)")
        do {
            let result = try await downloader.download(
                from: url,
                to: partial,
                allowsExpensiveNetwork: allowsExpensiveNetwork()
            )
            try Task.checkCancellation()
            guard result.bytesWritten > 0 else {
                throw CacheError.emptyDownload
            }
            if let expected = result.expectedBytes, expected > 0, expected != result.bytesWritten {
                throw CacheError.sizeMismatch(expected: expected, actual: result.bytesWritten)
            }
            ensureDirectory()
            let finalURL = directory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: finalURL)
            try FileManager.default.moveItem(at: partial, to: finalURL)
            let entry = AudioCacheEntry(
                trackID: track.id,
                quality: Self.qualityName(quality),
                fileName: fileName,
                format: format,
                duration: duration,
                byteSize: result.bytesWritten,
                title: track.title,
                artist: track.displayArtist,
                artworkURL: track.artworkURL
            )
            ensureDirectory()
            Self.write(entry: entry, named: name, in: directory)
            log("cache download finish key=\(name) bytes=\(result.bytesWritten)")
            evictIfNeeded()
        } catch {
            try? FileManager.default.removeItem(at: partial)
            if Task.isCancelled {
                log("cache cancel key=\(name) reason=\(cancelReason(for: name))")
            } else {
                log("cache download failed key=\(name) reason=\(error.localizedDescription)")
            }
        }
        cancelReasons[name] = nil
    }

    // MARK: - Maintenance

    public func sizeBytes() -> Int {
        cachedTracks().reduce(0) { $0 + $1.byteSize }
    }

    /// Count and bytes in one directory scan for the Settings row.
    public func stats() -> (count: Int, bytes: Int) {
        let tracks = cachedTracks()
        return (tracks.count, tracks.reduce(0) { $0 + $1.byteSize })
    }

    public func entryCount() -> Int {
        cachedTracks().count
    }

    /// Complete entries only, newest use first. Used by the Settings list.
    public func cachedTracks() -> [CachedTrackSummary] {
        Self.entries(in: directory).compactMap { entry in
            let fileURL = directory.appendingPathComponent(entry.fileName)
            guard let size = Self.fileSize(fileURL), size == entry.byteSize, size > 0 else {
                return nil
            }
            return CachedTrackSummary(
                trackID: entry.trackID,
                quality: entry.quality,
                fileName: entry.fileName,
                title: entry.title,
                artist: entry.artist,
                artworkURL: entry.artworkURL,
                byteSize: entry.byteSize,
                lastUsedAt: entry.lastUsedAt
            )
        }
        .sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    public func cancelDownload(for track: Track, quality: AudioQuality?, reason: String) async {
        let name = Self.storageBaseName(track: track, quality: quality)
        if cancelInFlight(named: name, reason: reason) {
            log("cache cancel key=\(name) reason=\(reason)")
        }
    }

    /// Removes one cached song without touching the rest of the cache.
    public func remove(trackID: String, qualityName: String) async {
        let name = Self.storageBaseName(trackID: trackID, qualityName: qualityName)
        _ = cancelInFlight(named: name, reason: "removed")
        guard let entry = Self.readEntry(named: name, in: directory) else {
            log("cache remove key=\(name) reason=not-found")
            return
        }
        removeFiles(named: name, entry: entry)
        log("cache remove key=\(name) bytes=\(entry.byteSize)")
    }

    @discardableResult
    private func cancelInFlight(named name: String, reason: String) -> Bool {
        let hadWork = inFlight[name] != nil || waiters.contains { $0.name == name }
        guard hadWork else { return false }
        cancelReasons[name] = reason
        if let entry = inFlight.removeValue(forKey: name) {
            entry.task.cancel()
            if activeTokens.remove(entry.id) != nil {
                admitWaiters()
            }
        }
        if let index = waiters.firstIndex(where: { $0.name == name }) {
            let queued = waiters.remove(at: index)
            queued.continuation.resume(returning: false)
        }
        return true
    }

    public func clear() {
        let entries = Self.entries(in: directory)
        let bytes = entries.reduce(0) { $0 + $1.byteSize }
        let running = inFlight
        inFlight.removeAll()
        for (name, entry) in running {
            cancelReasons[name] = "clear"
            entry.task.cancel()
        }
        for queued in waiters {
            queued.continuation.resume(returning: false)
        }
        waiters.removeAll()
        activeTokens.removeAll()
        try? FileManager.default.removeItem(at: directory)
        ensureDirectory()
        log("cache clear removed=\(entries.count) bytes=\(bytes)")
        if !running.isEmpty {
            log("cache slot released")
        }
    }

    public func purgePartials() {
        Self.removePartials(in: directory)
    }

    // MARK: - Download slot

    private func acquireSlot(id: UUID, name: String) async -> UUID? {
        guard !Task.isCancelled else {
            log("cache cancel key=\(name) reason=\(cancelReason(for: name))")
            return nil
        }
        if activeTokens.count < Self.maxConcurrentDownloads {
            activeTokens.insert(id)
            return id
        }
        log("cache wait key=\(name) active=\(activeTokens.count) waiting=\(waiters.count)")
        let admitted = await withCheckedContinuation { continuation in
            waiters.append(Waiter(id: id, name: name, continuation: continuation))
        }
        guard admitted else { return nil }
        guard !Task.isCancelled else {
            // The slot was handed over while this request was being cancelled.
            releaseSlot(token: id)
            return nil
        }
        return id
    }

    private func releaseSlot(token: UUID) {
        guard activeTokens.remove(token) != nil else { return }
        admitWaiters()
        if activeTokens.isEmpty {
            log("cache slot released")
        }
    }

    private func admitWaiters() {
        while activeTokens.count < Self.maxConcurrentDownloads, !waiters.isEmpty {
            let queued = waiters.removeFirst()
            activeTokens.insert(queued.id)
            queued.continuation.resume(returning: true)
        }
    }

    private func cancelReason(for name: String) -> String {
        cancelReasons[name] ?? "cancelled"
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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

    private static func hasCompleteEntry(named name: String, in directory: URL) -> Bool {
        guard let entry = readEntry(named: name, in: directory),
              let size = fileSize(directory.appendingPathComponent(entry.fileName)),
              size == entry.byteSize,
              size > 0 else { return false }
        return true
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
