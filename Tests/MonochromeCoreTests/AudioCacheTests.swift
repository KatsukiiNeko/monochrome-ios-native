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
        sizeLimitBytes: Int = AudioCache.defaultSizeLimitBytes
    ) -> AudioCache {
        AudioCache(
            directory: directory,
            downloader: downloader,
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
}

extension FakeDownloader {
    func setDelay(_ value: Duration) { delay = value }
    func setFailure(_ error: any Error) { failure = error }
}
