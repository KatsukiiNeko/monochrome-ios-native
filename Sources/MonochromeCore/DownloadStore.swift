// DownloadStore.swift: durable, user-initiated offline files, separate from the cache.
import Foundation

public struct DownloadedAudio: Equatable, Sendable {
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

public protocol DownloadedAudioProviding: Sendable {
    func downloadedFile(for track: Track) async -> DownloadedAudio?
}

public struct DownloadRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var trackID: String
    public var source: String
    public var quality: String
    public var title: String
    public var artist: String
    public var album: String
    public var artworkURL: URL?
    public var fileName: String
    public var format: AudioFormat?
    public var duration: Double?
    public var byteSize: Int
    public var completedAt: Date
    public var audioQuality: AudioQuality?

    public init(
        id: String,
        trackID: String,
        source: String,
        quality: String,
        title: String,
        artist: String,
        album: String,
        artworkURL: URL? = nil,
        fileName: String,
        format: AudioFormat? = nil,
        duration: Double? = nil,
        byteSize: Int,
        completedAt: Date = .now,
        audioQuality: AudioQuality? = nil
    ) {
        self.id = id
        self.trackID = trackID
        self.source = source
        self.quality = quality
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkURL = artworkURL
        self.fileName = fileName
        self.format = format
        self.duration = duration
        self.byteSize = byteSize
        self.completedAt = completedAt
        self.audioQuality = audioQuality
    }

    public var track: Track {
        let prefix = Track.remoteIDPrefix
        let streamID = trackID.hasPrefix(prefix) ? String(trackID.dropFirst(prefix.count)) : nil
        return Track(
            id: trackID,
            title: title,
            artist: artist,
            album: album,
            durationSeconds: duration,
            provider: source,
            streamID: streamID,
            artworkURL: artworkURL,
            audioQuality: audioQuality
        )
    }
}

public enum DownloadState: Equatable, Sendable {
    case queued
    case downloading(progress: Double?)
    case completed
    case failed(String)
    case cancelled
}

public struct DownloadItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var track: Track
    public var state: DownloadState
    public var record: DownloadRecord?

    public init(id: String, track: Track, state: DownloadState, record: DownloadRecord? = nil) {
        self.id = id
        self.track = track
        self.state = state
        self.record = record
    }
}

public enum DownloadError: LocalizedError, Equatable {
    case notStreaming
    case sourceNotEligible(String)
    case unsupportedFormat(String)
    case alreadyDownloaded
    case alreadyDownloading
    case lowStorage
    case emptyDownload
    case sizeMismatch(expected: Int, actual: Int)
    case recordWriteFailed
    case missingRecord

    public var errorDescription: String? {
        switch self {
        case .notStreaming: "Only streamed tracks can be downloaded."
        case .sourceNotEligible(let source): "Downloads are not available for \(source)."
        case .unsupportedFormat(let type): "This format cannot be saved for offline playback: \(type)."
        case .alreadyDownloaded: "This track is already downloaded."
        case .alreadyDownloading: "This track is already downloading."
        case .lowStorage: "There is not enough free space to download this track."
        case .emptyDownload: "The downloaded file was empty."
        case .sizeMismatch(let expected, let actual):
            "The downloaded file had \(actual) bytes instead of \(expected)."
        case .recordWriteFailed: "The download could not be saved."
        case .missingRecord: "The download record is missing."
        }
    }
}

/// Durable files in `Application Support/Downloads`. The temporary cache is a
/// different actor with a different root and cannot reach these files.
public actor DownloadStore: DownloadedAudioProviding {
    public static let recordFileName = "downloads.json"
    public static let minimumFreeSpaceBytes = 200 * 1024 * 1024
    public static let maxConcurrentDownloads = 2

    private struct Active {
        var track: Track
        var state: DownloadState
    }

    private let directory: URL
    private let downloader: any FileDownloader
    private let minimumFreeSpaceBytes: Int
    private let maxConcurrentDownloads: Int
    private let log: @Sendable (String) -> Void
    private var records: [String: DownloadRecord]
    private var active: [String: Active] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var activeSlots = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(
        directory: URL,
        downloader: any FileDownloader,
        minimumFreeSpaceBytes: Int = DownloadStore.minimumFreeSpaceBytes,
        maxConcurrentDownloads: Int = DownloadStore.maxConcurrentDownloads,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.directory = directory
        self.downloader = downloader
        self.minimumFreeSpaceBytes = minimumFreeSpaceBytes
        self.maxConcurrentDownloads = max(1, maxConcurrentDownloads)
        self.log = log
        self.records = Self.loadRecords(in: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Public state

    public func items() -> [DownloadItem] {
        let completed = records.values
            .sorted { $0.completedAt > $1.completedAt }
            .map {
                DownloadItem(
                    id: $0.id,
                    track: $0.track,
                    state: .completed,
                    record: $0
                )
            }
        let inProgress = active.values
            .sorted { $0.track.title.localizedCaseInsensitiveCompare($1.track.title) == .orderedAscending }
            .map {
                DownloadItem(
                    id: Self.identifier(for: $0.track, quality: $0.track.audioQuality),
                    track: $0.track,
                    state: $0.state
                )
            }
        return inProgress + completed
    }

    public func totalBytes() -> Int {
        records.values.reduce(0) { $0 + $1.byteSize }
    }

    public func isDownloaded(_ track: Track) -> Bool {
        records[Self.identifier(for: track, quality: track.audioQuality)] != nil
    }

    public func downloadedFile(for track: Track) async -> DownloadedAudio? {
        let id = Self.identifier(for: track, quality: track.audioQuality)
        guard let record = records[id] else { return nil }
        let url = directory.appendingPathComponent(record.fileName)
        guard let size = Self.fileSize(url), size == record.byteSize, size > 0 else {
            log("download missing id=\(id) reason=file")
            removeRecord(id: id, removeFile: true)
            return nil
        }
        return DownloadedAudio(
            url: url,
            format: record.format,
            duration: record.duration,
            byteSize: record.byteSize
        )
    }

    // MARK: - Download

    /// Awaits the actual transfer so callers can poll `items()` from another task.
    public func download(
        track: Track,
        url: URL,
        contentType: String?,
        format: AudioFormat?,
        duration: Double?
    ) async throws {
        guard track.isStreaming else { throw DownloadError.notStreaming }
        guard track.source.supportsDownloads else {
            throw DownloadError.sourceNotEligible(track.source.displayName)
        }
        guard CacheEligibility.isCacheable(url: url, contentType: contentType) else {
            throw DownloadError.unsupportedFormat(contentType ?? url.pathExtension)
        }
        let id = Self.identifier(for: track, quality: track.audioQuality)
        if let record = records[id] {
            let file = directory.appendingPathComponent(record.fileName)
            if let size = Self.fileSize(file), size == record.byteSize, size > 0 {
                throw DownloadError.alreadyDownloaded
            }
            removeRecord(id: id, removeFile: true)
        }
        if let entry = active[id] {
            switch entry.state {
            case .failed, .cancelled:
                active[id] = nil
            default:
                throw DownloadError.alreadyDownloading
            }
        }
        ensureDirectory()
        guard hasFreeSpace() else { throw DownloadError.lowStorage }

        active[id] = Active(track: track, state: .queued)
        log("download queued id=\(id)")
        let task = Task { [weak self] in
            guard let self else { return }
            await self.perform(
                track: track,
                url: url,
                contentType: contentType,
                format: format,
                duration: duration,
                id: id
            )
        }
        tasks[id] = task
        await task.value
        tasks[id] = nil
    }

    public func cancel(id: String) {
        tasks[id]?.cancel()
        if var entry = active[id] {
            entry.state = .cancelled
            active[id] = entry
        }
    }

    public func remove(id: String) throws {
        tasks[id]?.cancel()
        guard records[id] != nil else { throw DownloadError.missingRecord }
        removeRecord(id: id, removeFile: true)
    }

    // MARK: - Launch recovery

    /// Removes partial files, records whose file is gone, and orphan files.
    /// Never touches the temporary cache.
    public func reconcile() {
        Self.removePartials(in: directory)
        var repaired = records
        for (id, record) in records {
            let url = directory.appendingPathComponent(record.fileName)
            guard let size = Self.fileSize(url), size == record.byteSize, size > 0 else {
                log("download reconcile missing id=\(id)")
                repaired[id] = nil
                try? FileManager.default.removeItem(at: url)
                continue
            }
        }
        let referenced = Set(repaired.values.map(\.fileName))
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in files {
            let name = file.lastPathComponent
            if name == Self.recordFileName { continue }
            if file.pathExtension == "partial" || !referenced.contains(name) {
                try? FileManager.default.removeItem(at: file)
            }
        }
        records = repaired
        writeRecords()
        for (id, entry) in active {
            if case .queued = entry.state {
                active[id] = Active(track: entry.track, state: .failed("Interrupted"))
            } else if case .downloading = entry.state {
                active[id] = Active(track: entry.track, state: .failed("Interrupted"))
            }
        }
    }

    // MARK: - Transfer

    private func perform(
        track: Track,
        url: URL,
        contentType: String?,
        format: AudioFormat?,
        duration: Double?,
        id: String
    ) async {
        await acquireSlot()
        defer { releaseSlot() }
        guard !Task.isCancelled else {
            finish(id: id, state: .cancelled)
            return
        }
        ensureDirectory()
        guard hasFreeSpace() else {
            finish(id: id, state: .failed(DownloadError.lowStorage.localizedDescription))
            return
        }
        let ext = AudioFileType.fileExtension(forContentType: contentType)
        let fileName = "\(id.replacingOccurrences(of: ":", with: "_")).\(ext)"
        let partial = directory.appendingPathComponent("\(fileName).partial")
        try? FileManager.default.removeItem(at: partial)
        update(id: id, state: .downloading(progress: nil))
        log("download start id=\(id)")

        do {
            let result = try await downloader.download(
                from: url,
                to: partial,
                allowsExpensiveNetwork: true,
                onProgress: { [weak self] written, expected in
                    let progress = expected.map { expected in
                        expected > 0 ? min(1, Double(written) / Double(expected)) : nil
                    } ?? nil
                    Task { await self?.update(id: id, state: .downloading(progress: progress)) }
                }
            )
            try Task.checkCancellation()
            guard result.bytesWritten > 0 else { throw DownloadError.emptyDownload }
            if let expected = result.expectedBytes, expected > 0, expected != result.bytesWritten {
                throw DownloadError.sizeMismatch(expected: expected, actual: result.bytesWritten)
            }
            let finalURL = directory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: finalURL)
            try FileManager.default.moveItem(at: partial, to: finalURL)
            let record = DownloadRecord(
                id: id,
                trackID: track.id,
                source: track.source.rawValue,
                quality: Self.qualityName(track.audioQuality),
                title: track.title,
                artist: track.displayArtist,
                album: track.album,
                artworkURL: track.artworkURL,
                fileName: fileName,
                format: format,
                duration: duration,
                byteSize: result.bytesWritten,
                audioQuality: track.audioQuality
            )
            records[id] = record
            guard writeRecords() else {
                records[id] = nil
                try? FileManager.default.removeItem(at: finalURL)
                throw DownloadError.recordWriteFailed
            }
            active[id] = nil
            log("download finish id=\(id) bytes=\(result.bytesWritten)")
        } catch {
            try? FileManager.default.removeItem(at: partial)
            if Task.isCancelled {
                finish(id: id, state: .cancelled)
                log("download cancel id=\(id)")
            } else {
                finish(id: id, state: .failed(error.localizedDescription))
                log("download failed id=\(id) reason=\(error.localizedDescription)")
            }
        }
    }

    private func update(id: String, state: DownloadState) {
        guard var entry = active[id] else { return }
        entry.state = state
        active[id] = entry
    }

    private func finish(id: String, state: DownloadState) {
        guard var entry = active[id] else { return }
        entry.state = state
        active[id] = entry
    }

    // MARK: - Slot gate

    private func acquireSlot() async {
        if activeSlots < maxConcurrentDownloads {
            activeSlots += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        activeSlots += 1
    }

    private func releaseSlot() {
        activeSlots = max(0, activeSlots - 1)
        guard !waiters.isEmpty else { return }
        let next = waiters.removeFirst()
        next.resume()
    }

    // MARK: - Records

    private func removeRecord(id: String, removeFile: Bool) {
        guard let record = records.removeValue(forKey: id) else { return }
        if removeFile {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(record.fileName))
        }
        _ = writeRecords()
    }

    @discardableResult
    private func writeRecords() -> Bool {
        let ordered = records.values.sorted { $0.completedAt > $1.completedAt }
        guard let data = try? JSONEncoder().encode(ordered) else { return false }
        do {
            try data.write(
                to: directory.appendingPathComponent(Self.recordFileName),
                options: .atomic
            )
            return true
        } catch {
            log("download records write failed reason=\(error.localizedDescription)")
            return false
        }
    }

    private static func loadRecords(in directory: URL) -> [String: DownloadRecord] {
        let url = directory.appendingPathComponent(recordFileName)
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([DownloadRecord].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }

    // MARK: - Identity

    public static func identifier(for track: Track, quality: AudioQuality?) -> String {
        "\(track.source.rawValue):\(track.id):\(qualityName(quality))"
    }

    private static func qualityName(_ quality: AudioQuality?) -> String {
        quality?.rawValue.lowercased() ?? "default"
    }

    // MARK: - Files

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func hasFreeSpace() -> Bool {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: directory.path),
              let free = attributes[.systemFreeSize] as? NSNumber else { return true }
        return free.intValue > minimumFreeSpaceBytes
    }

    private static func fileSize(_ url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return nil }
        return size.intValue
    }

    private static func removePartials(in directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in files where file.pathExtension == "partial" {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
