// CatalogCacheTests.swift: TTL, stale-while-revalidate, LRU eviction and key normalization.
import Foundation
import Testing
@testable import MonochromeCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ start: Date) { date = start }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        date = date.addingTimeInterval(seconds)
        lock.unlock()
    }
}

private actor StubState {
    var calls = 0
    var payload: Data
    var status = 200
    var failure: (any Error)?

    init(payload: Data) { self.payload = payload }

    func recordCall() {
        calls += 1
    }

    func configure(payload: Data?, status: Int?, failure: (any Error)?) {
        if let payload { self.payload = payload }
        if let status { self.status = status }
        self.failure = failure
    }

    func next() -> (Data, Int, (any Error)?) {
        (payload, status, failure)
    }
}

private final class StubHTTP: HTTPClient, @unchecked Sendable {
    private let state: StubState

    init(payload: Data = Data("{}".utf8)) {
        state = StubState(payload: payload)
    }

    var callCount: Int {
        get async { await state.calls }
    }

    func set(payload: Data? = nil, status: Int? = nil, failure: (any Error)? = nil) async {
        await state.configure(payload: payload, status: status, failure: failure)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await state.recordCall()
        let (payload, status, failure) = await state.next()
        if let failure { throw failure }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
            throw HTTPClientError.invalidResponse
        }
        return (payload, response)
    }
}

private struct Offline: LocalizedError {
    var errorDescription: String? { "The Internet connection appears to be offline." }
}

private let searchURL = URL(string: "https://tracks.example/search/tracks?q=one&limit=25")!
private let otherSearchURL = URL(string: "https://tracks.example/search/tracks?q=two&limit=25")!
private let thirdSearchURL = URL(string: "https://tracks.example/search/tracks?q=three&limit=25")!
private let detailURL = URL(string: "https://tracks.example/releases/42")!

private func request(_ url: URL) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    return request
}

@Suite("Catalog request key")
struct CatalogRequestKeyTests {
    @Test("query order, host case, default port and fragments normalize away")
    func normalization() {
        let first = CatalogRequestKey(url: URL(string: "https://Tracks.Example:443/search/tracks?b=2&a=1#section")!)
        let second = CatalogRequestKey(url: URL(string: "https://tracks.example/search/tracks?a=1&b=2")!)
        #expect(first != nil)
        #expect(first == second)
        #expect(first?.kind == .search)
    }

    @Test("album and artist paths use the long-lived kind")
    func detailKind() {
        #expect(CatalogRequestKey(url: detailURL)?.kind == .detail)
        #expect(CatalogRequestKey(url: URL(string: "https://tracks.example/artists/7")!)?.kind == .detail)
    }

    @Test("stream paths and non-HTTP schemes are never cached")
    func rejectedRequests() {
        #expect(CatalogRequestKey(url: URL(string: "https://tracks.example/track/123")!) == nil)
        #expect(CatalogRequestKey(url: URL(string: "file:///tmp/a.flac")!) == nil)
        #expect(CatalogRequestKey(url: URL(string: "https:///no-host")!) == nil)
    }
}

@Suite("Catalog response cache")
struct CatalogResponseCacheTests {
    private var directory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("search responses expire after ten minutes, details after six hours")
    func timeToLive() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000_000))
        let cache = CatalogResponseCache(directory: directory, now: { clock.now() })
        let searchKey = CatalogRequestKey(url: searchURL)!
        let detailKey = CatalogRequestKey(url: detailURL)!
        await cache.store(data: Data("search".utf8), statusCode: 200, for: searchKey)
        await cache.store(data: Data("detail".utf8), statusCode: 200, for: detailKey)

        clock.advance(9 * 60)
        #expect(await cache.entry(for: searchKey)?.isFresh == true)
        clock.advance(2 * 60)
        #expect(await cache.entry(for: searchKey)?.isFresh == false)
        #expect(await cache.entry(for: detailKey)?.isFresh == true)
    }

    @Test("the least recently used entry is evicted when the budget fills")
    func lruEviction() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000_000))
        let payload = Data(repeating: 0x41, count: 120)
        let cache = CatalogResponseCache(directory: directory, capacityBytes: 300, now: { clock.now() })
        let first = CatalogRequestKey(url: searchURL)!
        let second = CatalogRequestKey(url: otherSearchURL)!
        let third = CatalogRequestKey(url: thirdSearchURL)!

        await cache.store(data: payload, statusCode: 200, for: first)
        clock.advance(1)
        await cache.store(data: payload, statusCode: 200, for: second)
        clock.advance(1)
        // Touch the first entry so the second becomes the least recently used.
        _ = await cache.entry(for: first)
        clock.advance(1)
        await cache.store(data: payload, statusCode: 200, for: third)

        #expect(await cache.entry(for: first) != nil)
        #expect(await cache.entry(for: second) == nil)
        #expect(await cache.entry(for: third) != nil)
        #expect(await cache.totalBytes() <= 300)
    }

    @Test("a response larger than the whole budget is rejected")
    func oversizedRejected() async {
        let cache = CatalogResponseCache(directory: directory, capacityBytes: 100)
        let key = CatalogRequestKey(url: searchURL)!
        await cache.store(data: Data(repeating: 0, count: 101), statusCode: 200, for: key)
        #expect(await cache.entry(for: key) == nil)
        #expect(await cache.entryCount() == 0)
    }

    @Test("entries survive a new cache instance and orphaned files are removed")
    func persistence() async throws {
        // One directory for the whole test: the helper mints a new path per access.
        let directory = self.directory
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000_000))
        let key = CatalogRequestKey(url: searchURL)!
        let first = CatalogResponseCache(directory: directory, now: { clock.now() })
        await first.store(data: Data("saved".utf8), statusCode: 200, for: key)
        let orphan = directory.appendingPathComponent("orphan.bin")
        try Data("orphan".utf8).write(to: orphan)

        let second = CatalogResponseCache(directory: directory, now: { clock.now() })
        #expect(await second.entry(for: key)?.response.data == Data("saved".utf8))
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test("a corrupt index quarantines and the cache starts empty")
    func corruptIndex() async throws {
        let directory = self.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: directory.appendingPathComponent("index.json"))
        let cache = CatalogResponseCache(directory: directory)
        #expect(await cache.entryCount() == 0)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains { $0.hasPrefix("index.corrupt-") })
    }
}

@Suite("Cached HTTP client")
struct CachedHTTPClientTests {
    private var directory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cached-http-\(UUID().uuidString)", isDirectory: true)
    }

    private func waitForCalls(_ stub: StubHTTP, _ expected: Int) async {
        for _ in 0..<200 {
            if await stub.callCount >= expected { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("a fresh hit answers without a second request")
    func freshHit() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000_000))
        let stub = StubHTTP(payload: Data("fresh".utf8))
        let cache = CatalogResponseCache(directory: directory, now: { clock.now() })
        let client = CachedHTTPClient(upstream: stub, cache: cache, now: { clock.now() })

        let (first, _) = try await client.data(for: request(searchURL))
        let (second, _) = try await client.data(for: request(searchURL))

        #expect(first == Data("fresh".utf8))
        #expect(second == first)
        #expect(await stub.callCount == 1)
    }

    @Test("a stale entry is served at once and refreshed in the background")
    func staleWhileRevalidate() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000_000))
        let stub = StubHTTP(payload: Data("old".utf8))
        let cache = CatalogResponseCache(directory: directory, now: { clock.now() })
        let client = CachedHTTPClient(upstream: stub, cache: cache, now: { clock.now() })
        _ = try await client.data(for: request(searchURL))

        await stub.set(payload: Data("new".utf8))
        clock.advance(11 * 60)
        let (stale, _) = try await client.data(for: request(searchURL))
        #expect(stale == Data("old".utf8))
        #expect(await stub.callCount == 1)

        await waitForCalls(stub, 2)
        let refreshed = await cache.entry(for: CatalogRequestKey(url: searchURL)!)
        #expect(refreshed?.response.data == Data("new".utf8))
        #expect(refreshed?.isFresh == true)
    }

    @Test("offline serves the stale copy instead of failing")
    func offlineServesStale() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000_000))
        let stub = StubHTTP(payload: Data("saved".utf8))
        let cache = CatalogResponseCache(directory: directory, now: { clock.now() })
        let client = CachedHTTPClient(upstream: stub, cache: cache, now: { clock.now() })
        _ = try await client.data(for: request(searchURL))

        await stub.set(payload: Data(), failure: Offline())
        clock.advance(24 * 60 * 60)
        let (data, response) = try await client.data(for: request(searchURL))
        #expect(data == Data("saved".utf8))
        #expect(response.statusCode == 200)
    }

    @Test("failures are not cached, so the next attempt reaches the network")
    func errorsAreNotCached() async throws {
        let stub = StubHTTP()
        let cache = CatalogResponseCache(directory: directory)
        let client = CachedHTTPClient(upstream: stub, cache: cache)

        await stub.set(payload: Data(), status: 500)
        _ = try await client.data(for: request(searchURL))
        #expect(await cache.entryCount() == 0)

        await stub.set(payload: Data(), failure: Offline())
        await #expect(throws: (any Error).self) {
            _ = try await client.data(for: request(searchURL))
        }
        #expect(await cache.entryCount() == 0)
    }

    @Test("stream paths bypass the cache entirely")
    func streamBypass() async throws {
        let stub = StubHTTP(payload: Data("audio".utf8))
        let cache = CatalogResponseCache(directory: directory)
        let client = CachedHTTPClient(upstream: stub, cache: cache)
        let url = URL(string: "https://tracks.example/track/123")!

        _ = try await client.data(for: request(url))
        _ = try await client.data(for: request(url))

        #expect(await stub.callCount == 2)
        #expect(await cache.entryCount() == 0)
    }
}
