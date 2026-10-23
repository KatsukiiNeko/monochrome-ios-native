// CacheRegressionTests.swift: regressions for clearing and serialising downloads.
import Foundation
import Testing
@testable import MonochromeCore

private func streamTrack(_ id: String) -> Track {
    Track(
        id: Track.remoteIDPrefix + id,
        title: "Stream \(id)",
        provider: "monochrome",
        streamID: id,
        audioQuality: .lossless
    )
}

private func makeDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
}

/// Blocks inside `download` until the test releases it, so clear/cancel races are reproducible.
private actor GateDownloader: FileDownloader {
    private(set) var calls = 0
    private var gates: [CheckedContinuation<Void, Never>] = []
    private let autoRelease: Bool
    var payload = Data(repeating: 9, count: 1_024)

    init(autoRelease: Bool = false) {
        self.autoRelease = autoRelease
    }

    func download(
        from url: URL,
        to destination: URL,
        allowsExpensiveNetwork: Bool
    ) async throws -> DownloadResult {
        calls += 1
        if !autoRelease {
            await withCheckedContinuation { gates.append($0) }
        }
        try Task.checkCancellation()
        try payload.write(to: destination)
        return DownloadResult(bytesWritten: payload.count, expectedBytes: payload.count)
    }

    func waitForCalls(_ target: Int) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while calls < target {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    func release() {
        let pending = gates
        gates.removeAll()
        for gate in pending { gate.resume() }
    }
}

private struct DownloadFailure: LocalizedError {
    var errorDescription: String? { "network unavailable" }
}

private actor FailOnceDownloader: FileDownloader {
    private(set) var calls = 0

    func download(
        from url: URL,
        to destination: URL,
        allowsExpensiveNetwork: Bool
    ) async throws -> DownloadResult {
        calls += 1
        if calls == 1 { throw DownloadFailure() }
        let payload = Data(repeating: 3, count: 512)
        try payload.write(to: destination)
        return DownloadResult(bytesWritten: payload.count, expectedBytes: payload.count)
    }
}

private func store(_ cache: AudioCache, _ track: Track) async {
    await cache.store(
        track,
        quality: track.audioQuality,
        url: URL(string: "https://tracks.example/track/\(track.streamID ?? "x")")!,
        contentType: "audio/flac",
        format: AudioFormat(codec: "flac", bitDepth: 16, sampleRateHz: 44_100),
        duration: 200
    )
}

@Suite("AudioCache regressions")
struct AudioCacheRegressionTests {
    @Test func storeClearStoreHitsAgain() async {
        let directory = makeDirectory()
        let cache = AudioCache(
            directory: directory,
            downloader: GateDownloader(autoRelease: true),
            minimumFreeSpaceBytes: 0
        )
        let track = streamTrack("1")

        await store(cache, track)
        await cache.clear()
        #expect(await cache.sizeBytes() == 0)

        await store(cache, track)
        #expect(await cache.cachedAudio(for: track, quality: .lossless) != nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func clearDuringDownloadDiscardsItAndAllowsANewOne() async {
        let directory = makeDirectory()
        let downloader = GateDownloader()
        let cache = AudioCache(directory: directory, downloader: downloader, minimumFreeSpaceBytes: 0)
        let track = streamTrack("1")

        let first = Task { await store(cache, track) }
        #expect(await downloader.waitForCalls(1))
        await cache.clear()
        await downloader.release()
        await first.value

        #expect(await cache.sizeBytes() == 0)
        #expect(await cache.cachedAudio(for: track, quality: .lossless) == nil)

        let second = Task { await store(cache, track) }
        #expect(await downloader.waitForCalls(2))
        await downloader.release()
        await second.value

        let calls = await downloader.calls
        #expect(calls == 2)
        #expect(await cache.cachedAudio(for: track, quality: .lossless) != nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func clearMidFlightThenTheSameKeyDownloadsAgain() async {
        let directory = makeDirectory()
        let downloader = GateDownloader()
        let cache = AudioCache(directory: directory, downloader: downloader, minimumFreeSpaceBytes: 0)
        let track = streamTrack("1")

        let first = Task { await store(cache, track) }
        #expect(await downloader.waitForCalls(1))
        await cache.clear()
        let second = Task { await store(cache, track) }
        await downloader.release()
        await first.value

        #expect(await downloader.waitForCalls(2))
        await downloader.release()
        await second.value

        let calls = await downloader.calls
        #expect(calls == 2)
        #expect(await cache.cachedAudio(for: track, quality: .lossless) != nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func threeSequentialDownloadsAllHit() async {
        let directory = makeDirectory()
        let downloader = GateDownloader()
        let cache = AudioCache(directory: directory, downloader: downloader, minimumFreeSpaceBytes: 0)

        for id in ["1", "2", "3"] {
            let task = Task { await store(cache, streamTrack(id)) }
            #expect(await downloader.waitForCalls(Int(id)!))
            await downloader.release()
            await task.value
        }

        for id in ["1", "2", "3"] {
            #expect(await cache.cachedAudio(for: streamTrack(id), quality: .lossless) != nil)
        }
        #expect(await cache.entryCount() == 3)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func aNewActorRecognisesExistingEntries() async {
        let directory = makeDirectory()
        let downloader = GateDownloader()
        let track = streamTrack("1")
        let first = AudioCache(directory: directory, downloader: downloader, minimumFreeSpaceBytes: 0)
        let task = Task { await store(first, track) }
        #expect(await downloader.waitForCalls(1))
        await downloader.release()
        await task.value

        let second = AudioCache(directory: directory, downloader: downloader, minimumFreeSpaceBytes: 0)
        #expect(await second.cachedAudio(for: track, quality: .lossless) != nil)
        #expect(await second.entryCount() == 1)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func twoDownloadsStartWithoutWaitingForTheFirst() async {
        let directory = makeDirectory()
        let downloader = GateDownloader()
        let cache = AudioCache(directory: directory, downloader: downloader, minimumFreeSpaceBytes: 0)

        let first = Task { await store(cache, streamTrack("1")) }
        #expect(await downloader.waitForCalls(1))
        let second = Task { await store(cache, streamTrack("2")) }
        #expect(await downloader.waitForCalls(2))

        await downloader.release()
        await first.value
        await second.value

        #expect(await cache.cachedAudio(for: streamTrack("1"), quality: .lossless) != nil)
        #expect(await cache.cachedAudio(for: streamTrack("2"), quality: .lossless) != nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func aThirdDownloadWaitsForOneOfTwoSlots() async {
        let directory = makeDirectory()
        let downloader = GateDownloader()
        let cache = AudioCache(directory: directory, downloader: downloader, minimumFreeSpaceBytes: 0)

        let first = Task { await store(cache, streamTrack("1")) }
        #expect(await downloader.waitForCalls(1))
        let second = Task { await store(cache, streamTrack("2")) }
        #expect(await downloader.waitForCalls(2))
        let third = Task { await store(cache, streamTrack("3")) }
        try? await Task.sleep(for: .milliseconds(100))
        let callsBeforeRelease = await downloader.calls
        #expect(callsBeforeRelease == 2)

        await downloader.release()
        #expect(await downloader.waitForCalls(3))
        await downloader.release()
        await first.value
        await second.value
        await third.value

        let callsAfter = await downloader.calls
        #expect(callsAfter == 3)
        #expect(await cache.entryCount() == 3)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func aFailedDownloadReleasesTheSlot() async {
        let directory = makeDirectory()
        let downloader = FailOnceDownloader()
        let cache = AudioCache(directory: directory, downloader: downloader, minimumFreeSpaceBytes: 0)

        await store(cache, streamTrack("1"))
        #expect(await cache.entryCount() == 0)
        await store(cache, streamTrack("2"))

        let calls = await downloader.calls
        #expect(calls == 2)
        #expect(await cache.cachedAudio(for: streamTrack("2"), quality: .lossless) != nil)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func cancellingTheActiveDownloadReleasesTheSlot() async {
        let directory = makeDirectory()
        let downloader = GateDownloader()
        let cache = AudioCache(directory: directory, downloader: downloader, minimumFreeSpaceBytes: 0)
        let first = streamTrack("1")

        let task = Task { await store(cache, first) }
        #expect(await downloader.waitForCalls(1))
        await cache.cancelDownload(for: first, quality: .lossless, reason: "skipped")
        await downloader.release()
        await task.value

        let second = Task { await store(cache, streamTrack("2")) }
        #expect(await downloader.waitForCalls(2))
        await downloader.release()
        await second.value

        let calls = await downloader.calls
        #expect(calls == 2)
        #expect(await cache.cachedAudio(for: first, quality: .lossless) == nil)
        #expect(await cache.cachedAudio(for: streamTrack("2"), quality: .lossless) != nil)
        try? FileManager.default.removeItem(at: directory)
    }
}
