// FailoverTests.swift: host cooldowns, rotation rules and the user host list.
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

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func append(_ url: URL?) {
        guard let url else { return }
        lock.lock()
        storage.append(url)
        lock.unlock()
    }

    var hosts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage.compactMap(\.host)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }
}

/// Serves per-host responses so rotation is observable.
private final class HostStub: HTTPClient, @unchecked Sendable {
    private let statuses: [String: Int]
    private let retryAfter: String?
    private let log = RequestLog()

    init(statuses: [String: Int], retryAfter: String? = nil) {
        self.statuses = statuses
        self.retryAfter = retryAfter
    }

    var requestLog: RequestLog { log }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        log.append(request.url)
        let host = request.url?.host ?? ""
        let status = statuses[host] ?? 200
        var headers = ["Content-Type": "application/json"]
        if let retryAfter { headers["Retry-After"] = retryAfter }
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
              ) else {
            throw HTTPClientError.invalidResponse
        }
        return (Data(#"{"tracks":[]}"#.utf8), response)
    }
}

private let hostA = URL(string: "https://first.test")!
private let hostB = URL(string: "https://second.test")!
private let hostC = URL(string: "https://third.test")!

@Suite("Host cooldowns")
struct HostCooldownsTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("delays double from 30 seconds and stop at ten minutes")
    func backoff() {
        var cooldowns = HostCooldowns()
        var date = start
        var delays: [TimeInterval] = []
        for _ in 0..<7 {
            cooldowns.penalize(hostA, at: date)
            let delay = secondsUntilReady(cooldowns, hostA, date)
            delays.append(delay)
            // Move past the deadline so the next failure is the next attempt.
            date = date.addingTimeInterval(delay)
        }
        #expect(delays.prefix(5) == [30, 60, 120, 240, 480])
        #expect(delays[5] == 600)
        #expect(delays[6] == 600)
    }

    private func secondsUntilReady(_ cooldowns: HostCooldowns, _ host: URL, _ date: Date) -> TimeInterval {
        var probe = date
        var seconds: TimeInterval = 0
        while cooldowns.isCoolingDown(host, at: probe) && seconds <= HostCooldowns.maximumDelay + 1 {
            seconds += 1
            probe = probe.addingTimeInterval(1)
        }
        return seconds
    }

    @Test("success clears the cooldown and the failure count")
    func reset() {
        var cooldowns = HostCooldowns()
        cooldowns.penalize(hostA, at: start)
        #expect(cooldowns.isCoolingDown(hostA, at: start.addingTimeInterval(10)))
        cooldowns.reset(hostA)
        #expect(!cooldowns.isCoolingDown(hostA, at: start))
        #expect(cooldowns.failureCount(hostA) == 0)
    }

    @Test("a cooldown ends when its deadline passes")
    func expiry() {
        var cooldowns = HostCooldowns()
        cooldowns.penalize(hostA, at: start)
        #expect(cooldowns.isCoolingDown(hostA, at: start.addingTimeInterval(29)))
        #expect(!cooldowns.isCoolingDown(hostA, at: start.addingTimeInterval(31)))
    }

    @Test("Retry-After wins when it asks for longer than the backoff")
    func retryAfterLonger() {
        var cooldowns = HostCooldowns()
        cooldowns.penalize(hostA, at: start, minimum: 300)
        #expect(cooldowns.isCoolingDown(hostA, at: start.addingTimeInterval(299)))
        #expect(!cooldowns.isCoolingDown(hostA, at: start.addingTimeInterval(301)))
    }

    @Test("Retry-After parses seconds, an HTTP date and rejects garbage")
    func retryAfterParsing() {
        let seconds = HTTPURLResponse(
            url: hostA, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "120"]
        )
        #expect(HostCooldowns.retryAfter(from: seconds!, at: start) == 120)

        let missing = HTTPURLResponse(url: hostA, statusCode: 429, httpVersion: nil, headerFields: nil)
        #expect(HostCooldowns.retryAfter(from: missing!, at: start) == nil)

        let garbage = HTTPURLResponse(
            url: hostA, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "soon"]
        )
        #expect(HostCooldowns.retryAfter(from: garbage!, at: start) == nil)

        let date = HTTPURLResponse(
            url: hostA,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "Tue, 17 Nov 2026 13:00:02 GMT"]
        )
        let parsed = HostCooldowns.retryAfter(
            from: date!,
            at: Date(timeIntervalSince1970: 1_763_384_400)
        )
        #expect(parsed != nil)
    }
}

@Suite("Catalog host failover")
struct CatalogHostFailoverTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("a rate limit without Retry-After stops instead of rotating")
    func rateLimitWithoutRetryAfter() async {
        let stub = HostStub(statuses: ["first.test": 429])
        let clock = FakeClock(start)
        let client = TracksAPIClient(baseURLs: [hostA, hostB], http: stub, now: { clock.now() })

        await #expect(throws: TracksAPIError.httpStatus(429)) {
            _ = try await client.searchTracks(matching: "anything")
        }
        #expect(stub.requestLog.count == 1)
    }

    @Test("a rate limit with Retry-After rotates and cools the host")
    func rateLimitWithRetryAfter() async throws {
        let stub = HostStub(statuses: ["first.test": 429], retryAfter: "120")
        let clock = FakeClock(start)
        let client = TracksAPIClient(baseURLs: [hostA, hostB], http: stub, now: { clock.now() })

        _ = try await client.searchTracks(matching: "anything")
        #expect(stub.requestLog.hosts == ["first.test", "second.test"])

        // The limited host is skipped while its cooldown runs.
        _ = try await client.searchTracks(matching: "anything")
        #expect(stub.requestLog.hosts == ["first.test", "second.test", "second.test"])
    }

    @Test("a server error cools the host for the next request")
    func serverErrorCoolsHost() async throws {
        let stub = HostStub(statuses: ["first.test": 503])
        let clock = FakeClock(start)
        let client = TracksAPIClient(baseURLs: [hostA, hostB], http: stub, now: { clock.now() })

        _ = try await client.searchTracks(matching: "anything")
        #expect(stub.requestLog.hosts == ["first.test", "second.test"])

        _ = try await client.searchTracks(matching: "anything")
        #expect(stub.requestLog.hosts == ["first.test", "second.test", "second.test"])
    }

    @Test("a healthy host is tried again once its cooldown expires")
    func recoveryAfterCooldown() async throws {
        let stub = HostStub(statuses: ["first.test": 503])
        let clock = FakeClock(start)
        let client = TracksAPIClient(baseURLs: [hostA, hostB], http: stub, now: { clock.now() })

        _ = try await client.searchTracks(matching: "anything")
        clock.advance(31)
        _ = try await client.searchTracks(matching: "anything")

        #expect(stub.requestLog.hosts == ["first.test", "second.test", "first.test", "second.test"])
    }

    @Test("only one cross-host retry happens per request")
    func singleRetry() async {
        let stub = HostStub(statuses: ["first.test": 500, "second.test": 500, "third.test": 500])
        let clock = FakeClock(start)
        let client = TracksAPIClient(baseURLs: [hostA, hostB, hostC], http: stub, now: { clock.now() })

        await #expect(throws: TracksAPIError.httpStatus(500)) {
            _ = try await client.searchTracks(matching: "anything")
        }
        #expect(stub.requestLog.count == 2)
    }

    @Test("a client error is reported without touching another host")
    func clientError() async {
        let stub = HostStub(statuses: ["first.test": 404, "second.test": 200])
        let clock = FakeClock(start)
        let client = TracksAPIClient(baseURLs: [hostA, hostB], http: stub, now: { clock.now() })

        await #expect(throws: TracksAPIError.httpStatus(404)) {
            _ = try await client.searchTracks(matching: "anything")
        }
        #expect(stub.requestLog.hosts == ["first.test"])
    }
}

@Suite("User catalog hosts")
struct UserCatalogHostTests {
    private func freshDefaults() -> UserDefaults {
        let name = "monochrome-hosts-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("HTTPS hosts are added in order and duplicates are refused")
    func addAndOrder() {
        let settings = StreamingSettings(defaults: freshDefaults())
        #expect(settings.userHosts.isEmpty)
        #expect(settings.addUserHost("https://one.test"))
        #expect(settings.addUserHost("https://two.test"))
        #expect(!settings.addUserHost("https://one.test"))
        #expect(!settings.addUserHost("http://plain.test"))
        #expect(!settings.addUserHost("   "))
        #expect(settings.userHosts.map(\.host) == ["one.test", "two.test"])
    }

    @Test("the list is capped, reordered, pruned and reset")
    func orderingAndCaps() {
        let settings = StreamingSettings(defaults: freshDefaults())
        for index in 0..<StreamingSettings.maximumUserHosts {
            #expect(settings.addUserHost("https://host\(index).test"))
        }
        #expect(!settings.addUserHost("https://overflow.test"))
        #expect(settings.userHosts.count == StreamingSettings.maximumUserHosts)

        settings.moveUserHost(from: 0, to: 2)
        #expect(settings.userHosts.first?.host == "host1.test")
        #expect(settings.userHosts[1].host == "host0.test")

        settings.removeUserHost(at: 1)
        #expect(settings.userHosts.count == StreamingSettings.maximumUserHosts - 1)

        settings.resetUserHosts()
        #expect(settings.userHosts.isEmpty)
    }

    @Test("the effective host order is user hosts, the endpoint, then the default")
    func effectiveOrder() {
        let settings = StreamingSettings(defaults: freshDefaults())
        settings.setBaseURL("https://custom.test")
        settings.addUserHost("https://one.test")
        #expect(settings.allHosts.map(\.host) == ["one.test", "custom.test", "tracks.monochrome.st"])

        settings.reset()
        #expect(settings.allHosts.map(\.host) == ["one.test", "tracks.monochrome.st"])

        // A user host that repeats the default does not take two turns.
        settings.resetUserHosts()
        settings.addUserHost(StreamingSettings.defaultBaseURL.absoluteString)
        #expect(settings.allHosts.count == 1)
    }
}
