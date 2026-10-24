// LyricsServiceTests.swift: cache-first loads, one retry, offline handling and cancellation.
import Foundation
import Testing
@testable import MonochromeCore

private enum FakeOutcome: Sendable {
    case result(LyricsResult)
    case error(LyricsProviderError)
}

private actor FakeRecorder {
    private var outcomes: [FakeOutcome]
    private(set) var calls = 0

    init(_ outcomes: [FakeOutcome]) {
        self.outcomes = outcomes
    }

    func next() throws -> LyricsResult {
        calls += 1
        guard !outcomes.isEmpty else { throw LyricsProviderError.invalidResponse }
        switch outcomes.removeFirst() {
        case .result(let result): return result
        case .error(let error): throw error
        }
    }
}

private struct FakeLyricsProvider: LyricsProviding {
    let sourceName = "Fake"
    let recorder: FakeRecorder

    func fetch(_ query: LyricsQuery) async throws -> LyricsResult {
        try await recorder.next()
    }
}

private struct SlowLyricsProvider: LyricsProviding {
    let sourceName = "Fake"

    func fetch(_ query: LyricsQuery) async throws -> LyricsResult {
        try await Task.sleep(for: .seconds(5))
        return LyricsResult(content: .notFound, source: sourceName)
    }
}

@Suite("LyricsService")
struct LyricsServiceTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func query() -> LyricsQuery {
        LyricsQuery(trackID: "track-1", title: "Synthetic Song", artist: "Synthetic Artist", duration: 200)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("lyrics-service-\(UUID().uuidString)", isDirectory: true)
    }

    private let found = LyricsResult(
        content: .synced([LyricLine(time: 1, text: "Synthetic line")]),
        source: "Fake"
    )

    @Test func aFreshCacheEntryAvoidsTheNetwork() async throws {
        let directory = temporaryDirectory()
        let recorder = FakeRecorder([.error(.offline)])
        let provider = FakeLyricsProvider(recorder: recorder)
        let cache = LyricsCache(directory: directory)
        await cache.store(found, for: query(), provider: "Fake", now: t0)
        let service = LyricsService(provider: provider, cache: cache, now: { self.t0 }, retryDelay: .zero)

        let result = try await service.load(query())

        #expect(result == found)
        #expect(await recorder.calls == 0)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func aTransientFailureIsRetriedOnce() async throws {
        let directory = temporaryDirectory()
        let recorder = FakeRecorder([.error(.transient), .result(found)])
        let service = LyricsService(
            provider: FakeLyricsProvider(recorder: recorder),
            cache: LyricsCache(directory: directory),
            now: { self.t0 },
            retryDelay: .zero
        )

        let result = try await service.load(query())

        #expect(result == found)
        #expect(await recorder.calls == 2)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func aSecondTransientFailureSurfacesAsUnavailable() async {
        let directory = temporaryDirectory()
        let recorder = FakeRecorder([.error(.transient), .error(.transient)])
        let service = LyricsService(
            provider: FakeLyricsProvider(recorder: recorder),
            cache: LyricsCache(directory: directory),
            now: { self.t0 },
            retryDelay: .zero
        )

        await #expect(throws: LyricsLoadError.offline) {
            _ = try await service.load(self.query())
        }
        #expect(await recorder.calls == 2)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func aRateLimitIsNotRetriedAndKeepsRetryAfter() async {
        let directory = temporaryDirectory()
        let recorder = FakeRecorder([.error(.rateLimited(retryAfter: 42)), .result(found)])
        let service = LyricsService(
            provider: FakeLyricsProvider(recorder: recorder),
            cache: LyricsCache(directory: directory),
            now: { self.t0 },
            retryDelay: .zero
        )

        await #expect(throws: LyricsLoadError.rateLimited(retryAfter: 42)) {
            _ = try await service.load(self.query())
        }
        #expect(await recorder.calls == 1)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func notFoundIsCachedAndNotQueriedAgain() async throws {
        let directory = temporaryDirectory()
        let missing = LyricsResult(content: .notFound, source: "Fake")
        let recorder = FakeRecorder([.result(missing), .error(.transient)])
        let service = LyricsService(
            provider: FakeLyricsProvider(recorder: recorder),
            cache: LyricsCache(directory: directory),
            now: { self.t0 },
            retryDelay: .zero
        )

        let first = try await service.load(query())
        let second = try await service.load(query())

        #expect(first.isNotFound)
        #expect(second.isNotFound)
        #expect(await recorder.calls == 1)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func offlineWithoutACacheReportsOffline() async {
        let directory = temporaryDirectory()
        let recorder = FakeRecorder([.error(.offline)])
        let service = LyricsService(
            provider: FakeLyricsProvider(recorder: recorder),
            cache: LyricsCache(directory: directory),
            now: { self.t0 },
            retryDelay: .zero
        )

        await #expect(throws: LyricsLoadError.offline) {
            _ = try await service.load(self.query())
        }
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func offlineServesAStaleEntry() async throws {
        let directory = temporaryDirectory()
        let cache = LyricsCache(directory: directory)
        await cache.store(found, for: query(), provider: "Fake", now: t0)
        let recorder = FakeRecorder([.error(.offline)])
        let at = t0.addingTimeInterval(90 * 24 * 60 * 60)
        let service = LyricsService(
            provider: FakeLyricsProvider(recorder: recorder),
            cache: cache,
            now: { at },
            retryDelay: .zero
        )

        let result = try await service.load(query())

        #expect(result == found)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func anUnqueryableTrackIsRejectedWithoutCallingTheProvider() async {
        let directory = temporaryDirectory()
        let recorder = FakeRecorder([.result(found)])
        let service = LyricsService(
            provider: FakeLyricsProvider(recorder: recorder),
            cache: LyricsCache(directory: directory),
            now: { self.t0 },
            retryDelay: .zero
        )
        let empty = LyricsQuery(trackID: "1", title: "", artist: "", duration: nil)

        await #expect(throws: LyricsLoadError.unavailable) {
            _ = try await service.load(empty)
        }
        #expect(await recorder.calls == 0)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func cancellingTheTaskStopsTheLoad() async {
        let directory = temporaryDirectory()
        let service = LyricsService(
            provider: SlowLyricsProvider(),
            cache: LyricsCache(directory: directory),
            now: { self.t0 },
            retryDelay: .zero
        )
        let query = self.query()
        let task = Task { try await service.load(query) }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        try? FileManager.default.removeItem(at: directory)
    }
}
