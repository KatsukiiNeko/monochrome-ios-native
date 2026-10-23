// DownloadStoreTests.swift: durable offline files, recovery and eligibility.
import Foundation
import Testing
@testable import MonochromeCore

private actor DownloadFake: FileDownloader {
    var payload: Data
    var failure: (any Error)?
    var delay: Duration = .zero
    private(set) var calls = 0
    private(set) var active = 0
    private(set) var peak = 0

    init(payload: Data = Data(repeating: 9, count: 256)) {
        self.payload = payload
    }

    func download(
        from url: URL,
        to destination: URL,
        allowsExpensiveNetwork: Bool
    ) async throws -> DownloadResult {
        calls += 1
        active += 1
        peak = max(peak, active)
        defer { active -= 1 }
        if delay > .zero { try? await Task.sleep(for: delay) }
        if let failure { throw failure }
        try payload.write(to: destination)
        return DownloadResult(bytesWritten: payload.count, expectedBytes: payload.count)
    }

    func setDelay(_ value: Duration) { delay = value }
    func setFailure(_ error: any Error) { failure = error }
    func peakConcurrency() -> Int { peak }
    func callCount() -> Int { calls }
}

private func downloadTrack(_ id: String = "1", provider: String = "monochrome") -> Track {
    Track(
        id: Track.remoteIDPrefix + id,
        title: "Download \(id)",
        artist: "Artist",
        album: "Album",
        durationSeconds: 180,
        provider: provider,
        streamID: id,
        audioQuality: .lossless
    )
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

@Suite("DownloadStore")
struct DownloadStoreTests {
    private func makeStore(
        directory: URL,
        downloader: DownloadFake,
        maxConcurrent: Int = 2
    ) -> DownloadStore {
        DownloadStore(
            directory: directory,
            downloader: downloader,
            minimumFreeSpaceBytes: 0,
            maxConcurrentDownloads: maxConcurrent
        )
    }

    private func download(
        _ store: DownloadStore,
        _ track: Track,
        url: URL = URL(string: "https://tracks.example/track/1")!
    ) async throws {
        try await store.download(
            track: track,
            url: url,
            contentType: "audio/flac",
            format: AudioFormat(codec: "flac"),
            duration: track.durationSeconds
        )
    }

    @Test func completedDownloadPersistsAcrossStores() async throws {
        let directory = temporaryDirectory()
        let track = downloadTrack()
        let store = makeStore(directory: directory, downloader: DownloadFake())

        try await download(store, track)

        let items = await store.items()
        #expect(items.count == 1)
        #expect(items.first?.state == .completed)
        #expect(await store.isDownloaded(track))
        let audio = try #require(await store.downloadedFile(for: track))
        #expect(FileManager.default.fileExists(atPath: audio.url.path))

        let reopened = makeStore(directory: directory, downloader: DownloadFake())
        #expect(await reopened.isDownloaded(track))
        #expect(await reopened.totalBytes() == 256)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func duplicateDownloadIsRefused() async throws {
        let directory = temporaryDirectory()
        let track = downloadTrack()
        let store = makeStore(directory: directory, downloader: DownloadFake())
        try await download(store, track)

        await #expect(throws: DownloadError.alreadyDownloaded) {
            try await download(store, track)
        }
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func ineligibleSourceIsRefused() async throws {
        let directory = temporaryDirectory()
        let store = makeStore(directory: directory, downloader: DownloadFake())
        let track = downloadTrack(provider: "youTubeMusic")

        await #expect(throws: DownloadError.sourceNotEligible(MusicSourceID.youTubeMusic.displayName)) {
            try await download(store, track)
        }
        #expect(await store.items().isEmpty)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func hlsAndDashAreRefused() async throws {
        let directory = temporaryDirectory()
        let store = makeStore(directory: directory, downloader: DownloadFake())

        await #expect(throws: DownloadError.unsupportedFormat("application/vnd.apple.mpegurl")) {
            try await store.download(
                track: downloadTrack(),
                url: URL(string: "https://x/y.m3u8")!,
                contentType: "application/vnd.apple.mpegurl",
                format: nil,
                duration: nil
            )
        }
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func failedTransferLeavesNoCompletedRecord() async throws {
        let directory = temporaryDirectory()
        let downloader = DownloadFake()
        await downloader.setFailure(URLError(.notConnectedToInternet))
        let store = makeStore(directory: directory, downloader: downloader)

        try? await download(store, downloadTrack())

        let item = try #require(await store.items().first)
        if case .failed(let reason) = item.state {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("expected failed state, got \(item.state)")
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(!files.contains { $0.hasSuffix(".partial") })
        #expect(!files.contains(DownloadStore.recordFileName))
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func reconcileRemovesMissingRecordsAndOrphans() async throws {
        let directory = temporaryDirectory()
        let store = makeStore(directory: directory, downloader: DownloadFake())
        let track = downloadTrack()
        try await download(store, track)

        let audio = try #require(await store.downloadedFile(for: track))
        try FileManager.default.removeItem(at: audio.url)
        try Data("partial".utf8).write(to: directory.appendingPathComponent("x.flac.partial"))
        try Data("orphan".utf8).write(to: directory.appendingPathComponent("orphan.flac"))

        await store.reconcile()

        #expect(await store.items().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: audio.url.path))
        let files = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        #expect(!files.contains("x.flac.partial"))
        #expect(!files.contains("orphan.flac"))
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func missingFileRepairsTheRecordOnLookup() async throws {
        let directory = temporaryDirectory()
        let store = makeStore(directory: directory, downloader: DownloadFake())
        let track = downloadTrack()
        try await download(store, track)
        let audio = try #require(await store.downloadedFile(for: track))
        try FileManager.default.removeItem(at: audio.url)

        #expect(await store.downloadedFile(for: track) == nil)
        #expect(await store.items().isEmpty)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func missingFileCanBeDownloadedAgain() async throws {
        let directory = temporaryDirectory()
        let store = makeStore(directory: directory, downloader: DownloadFake())
        let track = downloadTrack()
        try await download(store, track)
        let audio = try #require(await store.downloadedFile(for: track))
        try FileManager.default.removeItem(at: audio.url)

        try await download(store, track)

        #expect(await store.isDownloaded(track))
        #expect(await store.downloadedFile(for: track) != nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func removalDeletesFileAndRecord() async throws {
        let directory = temporaryDirectory()
        let store = makeStore(directory: directory, downloader: DownloadFake())
        let track = downloadTrack()
        try await download(store, track)
        let item = try #require(await store.items().first)
        let audio = try #require(await store.downloadedFile(for: track))

        try await store.remove(id: item.id)

        #expect(!FileManager.default.fileExists(atPath: audio.url.path))
        #expect(await store.items().isEmpty)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func twoDownloadsRunAtOnceAndAThirdWaits() async throws {
        let directory = temporaryDirectory()
        let downloader = DownloadFake()
        await downloader.setDelay(.milliseconds(80))
        let store = makeStore(directory: directory, downloader: downloader)

        async let one: Void = download(store, downloadTrack("1"))
        async let two: Void = download(store, downloadTrack("2"))
        async let three: Void = download(store, downloadTrack("3"))
        _ = try await (one, two, three)

        #expect(await downloader.peakConcurrency() == 2)
        #expect(await store.items().count == 3)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func recordRoundTripKeepsStableIdentity() async throws {
        let directory = temporaryDirectory()
        let track = downloadTrack()
        let store = makeStore(directory: directory, downloader: DownloadFake())
        try await download(store, track)
        let record = try #require(await store.items().first?.record)

        #expect(record.id == DownloadStore.identifier(for: track, quality: .lossless))
        #expect(record.source == "monochrome")
        #expect(record.trackID == track.id)
        #expect(record.track.streamID == track.streamID)
        #expect(record.title == track.title)
        #expect(record.format == AudioFormat(codec: "flac"))
        try? FileManager.default.removeItem(at: directory)
    }
}
