// AudioCacheTests.swift: cache behaviour with a fake downloader and temporary directories.
import Foundation
import Testing
@testable import MonochromeCore

private struct DownloadFailure: LocalizedError {
    var errorDescription: String? { "network unavailable" }
}

private actor FakeDownloader: FileDownloader {
    private(set) var calls: [URL] = []
    var payload: Data
    var declaredBytes: Int?
    var failure: (any Error)?
    var delay: Duration = .zero

    init(payload: Data = Data(repeating: 7, count: 512), declaredBytes: Int? = nil) {
        self.payload = payload
        self.declaredBytes = declaredBytes
    }

    func download(
        from url: URL,
        to destination: URL,
        allowsExpensiveNetwork: Bool
    ) async throws -> DownloadResult {
        calls.append(url)
        if delay > .zero { try? await Task.sleep(for: delay) }
        if let failure { throw failure }
        try payload.write(to: destination)
        return DownloadResult(bytesWritten: payload.count, expectedBytes: declaredBytes ?? payload.count)
    }

    func callCount() -> Int { calls.count }
}

private func streamTrack(_ id: String = "1", quality: AudioQuality? = .lossless) -> Track {
    Track(
        id: Track.remoteIDPrefix + id,
        title: "Stream \(id)",
        provider: "monochrome",
        streamID: id,
        audioQuality: quality
    )
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

@Suite("AudioCache")
struct AudioCacheTests {
    private func makeCache(
        directory: URL,
        downloader: FakeDownloader,
        entryLimit: Int = AudioCache.defaultEntryLimit,
        sizeLimitBytes: Int = AudioCache.defaultSizeLimitBytes
    ) -> AudioCache {
        AudioCache(
            directory: directory,
            downloader: downloader,
            entryLimit: entryLimit,
            sizeLimitBytes: sizeLimitBytes,
            minimumFreeSpaceBytes: 0
        )
    }

    private func store(
        _ cache: AudioCache,
        _ track: Track,
        url: URL = URL(string: "https://tracks.example/track/1")!
    ) async {
        await cache.store(
            track,
            quality: track.audioQuality,
            url: url,
            contentType: "audio/flac",
            format: AudioFormat(codec: "flac", bitDepth: 16, sampleRateHz: 44_100),
            duration: 200
        )
    }

    @Test func missThenStoreThenHit() async throws {
        let directory = temporaryDirectory()
        let downloader = FakeDownloader()
        let cache = makeCache(directory: directory, downloader: downloader)
        let track = streamTrack()

        #expect(await cache.cachedAudio(for: track, quality: .lossless) == nil)

        await store(cache, track)

        let hit = await cache.cachedAudio(for: track, quality: .lossless)
        #expect(hit != nil)
        #expect(hit?.url.pathExtension == "flac")
        #expect(hit?.byteSize == 512)
        #expect(hit?.duration == 200)
        #expect(hit?.format == AudioFormat(codec: "flac", bitDepth: 16, sampleRateHz: 44_100))
        let calls = await downloader.callCount()
        #expect(calls == 1)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func qualityIsPartOfTheKey() async throws {
        let directory = temporaryDirectory()
        let downloader = FakeDownloader()
        let cache = makeCache(directory: directory, downloader: downloader)
        let track = streamTrack()

        await store(cache, track)

        #expect(await cache.cachedAudio(for: track, quality: .hiResLossless) == nil)
        #expect(await cache.cachedAudio(for: track, quality: .lossless) != nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func truncatedFileIsAMissAndIsRemoved() async throws {
        let directory = temporaryDirectory()
        let downloader = FakeDownloader()
        let cache = makeCache(directory: directory, downloader: downloader)
        let track = streamTrack()
        await store(cache, track)
        let hit = try #require(await cache.cachedAudio(for: track, quality: .lossless))

        try Data(repeating: 1, count: 10).write(to: hit.url)

        #expect(await cache.cachedAudio(for: track, quality: .lossless) == nil)
        #expect(!FileManager.default.fileExists(atPath: hit.url.path))
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func sizeMismatchIsRejected() async throws {
        let directory = temporaryDirectory()
        let downloader = FakeDownloader(payload: Data(repeating: 1, count: 10), declaredBytes: 512)
        let cache = makeCache(directory: directory, downloader: downloader)
        let track = streamTrack()

        await store(cache, track)

        #expect(await cache.cachedAudio(for: track, quality: .lossless) == nil)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(files.filter { $0.hasSuffix(".partial") }.isEmpty)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func storeIsAtomicAndLeavesNoPartial() async throws {
        let directory = temporaryDirectory()
        let cache = makeCache(directory: directory, downloader: FakeDownloader())
        let track = streamTrack()

        await store(cache, track)

        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(files.contains { $0.hasSuffix(".flac") })
        #expect(files.contains { $0.hasSuffix(".json") })
        #expect(files.filter { $0.hasSuffix(".partial") }.isEmpty)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func evictionRemovesTheLeastRecentlyUsedEntry() async throws {
        let directory = temporaryDirectory()
        let cache = makeCache(directory: directory, downloader: FakeDownloader(), sizeLimitBytes: 1_024)
        let first = streamTrack("1")
        let second = streamTrack("2")

        await store(cache, first)
        try? await Task.sleep(for: .milliseconds(10))
        await store(cache, second)
        try? await Task.sleep(for: .milliseconds(10))
        _ = await cache.cachedAudio(for: first, quality: .lossless)
        try? await Task.sleep(for: .milliseconds(10))
        // A third entry pushes past the cap; the second is now the oldest.
        await store(cache, streamTrack("3"))

        #expect(await cache.cachedAudio(for: first, quality: .lossless) != nil)
        #expect(await cache.cachedAudio(for: second, quality: .lossless) == nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func hitRefreshesLastUsedAt() async throws {
        let directory = temporaryDirectory()
        let cache = makeCache(directory: directory, downloader: FakeDownloader())
        let track = streamTrack()
        await store(cache, track)

        let sidecar = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .first { $0.hasSuffix(".json") }
        let sc = try #require(sidecar)
        let before = try JSONDecoder().decode(
            AudioCacheEntry.self,
            from: Data(contentsOf: directory.appendingPathComponent(sc))
        ).lastUsedAt

        try? await Task.sleep(for: .milliseconds(20))
        _ = await cache.cachedAudio(for: track, quality: .lossless)

        let after = try JSONDecoder().decode(
            AudioCacheEntry.self,
            from: Data(contentsOf: directory.appendingPathComponent(sc))
        ).lastUsedAt
        #expect(after > before)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func concurrentStoresShareOneDownload() async throws {
        let directory = temporaryDirectory()
        let downloader = FakeDownloader()
        await downloader.setDelay(.milliseconds(100))
        let cache = makeCache(directory: directory, downloader: downloader)
        let track = streamTrack()

        async let one: Void = store(cache, track)
        async let two: Void = store(cache, track)
        _ = await (one, two)

        let calls = await downloader.callCount()
        #expect(calls == 1)
        #expect(await cache.cachedAudio(for: track, quality: .lossless) != nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func extensionFollowsTheManifestType() {
        #expect(AudioFileType.fileExtension(forContentType: "audio/flac") == "flac")
        #expect(AudioFileType.fileExtension(forContentType: "audio/mp4") == "m4a")
        #expect(AudioFileType.fileExtension(forContentType: "audio/mpeg") == "mp3")
        #expect(AudioFileType.fileExtension(forContentType: nil) == "audio")
        #expect(AudioFileType.fileExtension(forContentType: "audio/flac; charset=binary") == "flac")
    }

    @Test func playlistsAndEncryptedSourcesAreNotCacheable() {
        #expect(CacheEligibility.isCacheable(url: URL(string: "https://x/y.m3u8")!, contentType: "application/vnd.apple.mpegurl") == false)
        #expect(CacheEligibility.isCacheable(url: URL(string: "https://x/y.mpd")!, contentType: "application/dash+xml") == false)
        #expect(CacheEligibility.isCacheable(url: URL(string: "https://x/y")!, contentType: "audio/flac", isEncrypted: true) == false)
        #expect(CacheEligibility.isCacheable(url: URL(string: "https://x/y")!, contentType: "audio/flac") == true)
    }

    @Test func unsupportedSourcesAreSkipped() async throws {
        let directory = temporaryDirectory()
        let downloader = FakeDownloader()
        let cache = makeCache(directory: directory, downloader: downloader)

        await cache.store(
            streamTrack(),
            quality: .lossless,
            url: URL(string: "https://x/y.m3u8")!,
            contentType: "application/vnd.apple.mpegurl",
            format: nil,
            duration: nil
        )

        #expect(await downloader.callCount() == 0)
        #expect(await cache.sizeBytes() == 0)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func clearRemovesEverything() async throws {
        let directory = temporaryDirectory()
        let cache = makeCache(directory: directory, downloader: FakeDownloader())
        await store(cache, streamTrack())
        #expect(await cache.sizeBytes() > 0)

        await cache.clear()

        #expect(await cache.sizeBytes() == 0)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func cachedTracksCarryMetadataAndCanBeRemovedIndividually() async throws {
        let directory = temporaryDirectory()
        let cache = makeCache(directory: directory, downloader: FakeDownloader())
        let first = streamTrack("1")
        let second = streamTrack("2")
        await store(cache, first)
        await store(cache, second)

        let summaries = await cache.cachedTracks()
        #expect(summaries.count == 2)
        #expect(Set(summaries.compactMap(\.title)) == ["Stream 1", "Stream 2"])
        let summary = try #require(summaries.first { $0.trackID == first.id })
        #expect(summary.artist == "Unknown artist")

        await cache.remove(trackID: summary.trackID, qualityName: summary.quality)

        #expect(await cache.cachedAudio(for: first, quality: .lossless) == nil)
        #expect(await cache.cachedAudio(for: second, quality: .lossless) != nil)
        #expect(await cache.cachedTracks().count == 1)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func legacySidecarWithoutDisplayMetadataDecodes() throws {
        let json = #"{"trackID":"stream:1","quality":"lossless","fileName":"x.flac","byteSize":10,"lastUsedAt":0}"#
        let entry = try JSONDecoder().decode(AudioCacheEntry.self, from: Data(json.utf8))

        #expect(entry.title == nil)
        #expect(entry.artist == nil)
        #expect(entry.artworkURL == nil)
        #expect(entry.createdAt == .distantPast)
    }

    @Test func loadedEntryIsNeverEvicted() async throws {
        let directory = temporaryDirectory()
        let cache = makeCache(directory: directory, downloader: FakeDownloader(), entryLimit: 2)
        let first = streamTrack("1")
        await store(cache, first)
        await cache.protect(track: first, quality: .lossless)

        for id in 2...6 {
            await store(cache, streamTrack(String(id)))
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(await cache.entryCount() == 2)
        #expect(await cache.cachedAudio(for: first, quality: .lossless) != nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func equalTimestampsUseCreationTimeThenKey() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = Date(timeIntervalSince1970: 100)
        for (id, name) in [("stream:2", "stream_2-lossless"), ("stream:1", "stream_1-lossless")] {
            try Data(repeating: 3, count: 32).write(
                to: directory.appendingPathComponent("\(name).flac")
            )
            let entry = AudioCacheEntry(
                trackID: id,
                quality: "lossless",
                fileName: "\(name).flac",
                byteSize: 32,
                lastUsedAt: stamp,
                createdAt: stamp
            )
            let data = try JSONEncoder().encode(entry)
            try data.write(to: directory.appendingPathComponent("\(name).json"))
        }

        let cache = makeCache(directory: directory, downloader: FakeDownloader(), entryLimit: 1)
        await cache.reconcile()

        // Same use/creation time: the lexicographically smallest track id goes first.
        #expect(await cache.cachedAudio(for: streamTrack("2"), quality: .lossless) != nil)
        #expect(await cache.cachedAudio(for: streamTrack("1"), quality: .lossless) == nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func clearOnLaunchPreferencePersistsAndDefaultsOff() {
        let suite = "AudioCacheSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AudioCacheSettings(defaults: defaults)

        #expect(settings.clearOnLaunch == false)
        settings.setClearOnLaunch(true)
        #expect(AudioCacheSettings(defaults: defaults).clearOnLaunch)
        settings.setClearOnLaunch(false)
        #expect(AudioCacheSettings(defaults: defaults).clearOnLaunch == false)
    }

    @Test func downloaderFailureLeavesNothingBehind() async throws {
        let directory = temporaryDirectory()
        let downloader = FakeDownloader()
        await downloader.setFailure(DownloadFailure())
        let cache = makeCache(directory: directory, downloader: downloader)

        await store(cache, streamTrack())

        #expect(await cache.cachedAudio(for: streamTrack(), quality: .lossless) == nil)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(files.isEmpty)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func sixEntriesEvictTheLeastRecentlyUsedOne() async throws {
        let directory = temporaryDirectory()
        let cache = makeCache(directory: directory, downloader: FakeDownloader())
        let tracks = (1...6).map { streamTrack(String($0)) }

        for track in tracks.prefix(5) {
            await store(cache, track)
            try? await Task.sleep(for: .milliseconds(10))
        }
        // Touch track 1 so track 2 becomes the least recently used.
        #expect(await cache.cachedAudio(for: tracks[0], quality: .lossless) != nil)
        try? await Task.sleep(for: .milliseconds(10))
        await store(cache, tracks[5])

        #expect(await cache.entryCount() == AudioCache.defaultEntryLimit)
        #expect(await cache.cachedAudio(for: tracks[0], quality: .lossless) != nil)
        #expect(await cache.cachedAudio(for: tracks[1], quality: .lossless) == nil)
        #expect(await cache.cachedAudio(for: tracks[5], quality: .lossless) != nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func playingSixInOrderEvictsTheFirstAndKeepsTwoThroughSix() async throws {
        let directory = temporaryDirectory()
        let cache = makeCache(directory: directory, downloader: FakeDownloader())
        let tracks = (1...6).map { streamTrack(String($0)) }

        for track in tracks {
            await store(cache, track)
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(await cache.entryCount() == 5)
        #expect(await cache.cachedAudio(for: tracks[0], quality: .lossless) == nil)
        for track in tracks[1...] {
            #expect(await cache.cachedAudio(for: track, quality: .lossless) != nil)
        }
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func reconcileRemovesInterruptedAndOrphanedFiles() async throws {
        let directory = temporaryDirectory()
        let cache = makeCache(directory: directory, downloader: FakeDownloader())
        let track = streamTrack()
        await store(cache, track)

        try Data(repeating: 1, count: 8).write(
            to: directory.appendingPathComponent("orphan.flac.uuid.partial")
        )
        try Data(repeating: 2, count: 8).write(
            to: directory.appendingPathComponent("orphan.flac")
        )
        try Data("not json".utf8).write(
            to: directory.appendingPathComponent("orphan.json")
        )

        await cache.reconcile()

        let files = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        #expect(!files.contains { $0.hasSuffix(".partial") })
        #expect(!files.contains("orphan.flac"))
        #expect(!files.contains("orphan.json"))
        #expect(await cache.cachedAudio(for: track, quality: .lossless) != nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func reconcileAppliesTheEntryLimitToExistingCache() async throws {
        let directory = temporaryDirectory()
        let downloader = FakeDownloader()
        let large = makeCache(directory: directory, downloader: downloader, entryLimit: 6)
        for id in 1...6 {
            await store(large, streamTrack(String(id)))
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(await large.entryCount() == 6)

        let limited = makeCache(directory: directory, downloader: downloader, entryLimit: 5)
        await limited.reconcile()

        #expect(await limited.entryCount() == 5)
        #expect(await limited.cachedAudio(for: streamTrack("1"), quality: .lossless) == nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func clearingTheTemporaryCacheLeavesPermanentStorageAlone() async throws {
        let root = temporaryDirectory()
        let cacheDirectory = root.appendingPathComponent("AudioCache", isDirectory: true)
        let permanentDirectory = root.appendingPathComponent("Permanent", isDirectory: true)
        try FileManager.default.createDirectory(at: permanentDirectory, withIntermediateDirectories: true)
        let permanent = permanentDirectory.appendingPathComponent("saved.flac")
        try Data(repeating: 5, count: 64).write(to: permanent)

        let cache = makeCache(directory: cacheDirectory, downloader: FakeDownloader())
        await store(cache, streamTrack())
        await cache.clear()

        #expect(FileManager.default.fileExists(atPath: permanent.path))
        #expect(await cache.entryCount() == 0)
        try? FileManager.default.removeItem(at: root)
    }
}

extension FakeDownloader {
    func setDelay(_ value: Duration) { delay = value }
    func setFailure(_ error: any Error) { failure = error }
}
