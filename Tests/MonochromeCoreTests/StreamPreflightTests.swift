// StreamPreflightTests.swift: the bounded ladder in front of AVPlayer.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import MonochromeCore

private actor StubResponses {
    private var outcomes: [Result<Int, URLError>]
    private var last: Result<Int, URLError> = .success(206)
    private(set) var requests: [URLRequest] = []

    init(_ outcomes: [Result<Int, URLError>]) {
        self.outcomes = outcomes
    }

    /// The last outcome repeats, so a test can leave the origin cold forever.
    func next(_ request: URLRequest) -> Result<Int, URLError> {
        requests.append(request)
        if !outcomes.isEmpty { last = outcomes.removeFirst() }
        return last
    }
}

private struct StubHTTP: HTTPClient {
    let responses: StubResponses
    let headers: [String: String]

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        switch await responses.next(request) {
        case .success(let status):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/2",
                headerFields: status == 206
                    ? ["Content-Range": "bytes 0-1/1000", "Content-Length": "2"]
                    : headers
            )!
            return (Data([0, 0]), response)
        case .failure(let error):
            throw error
        }
    }
}

/// Records the waits instead of sleeping so the test runs instantly.
private final class RecordedSleep: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TimeInterval] = []

    func sleep(_ seconds: TimeInterval) async {
        record(seconds)
    }

    private func record(_ seconds: TimeInterval) {
        lock.lock()
        recorded.append(seconds)
        lock.unlock()
    }

    var delays: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

/// Hands out a fixed list of offsets in order.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var offsets: [TimeInterval]

    init(_ offsets: [TimeInterval]) {
        self.offsets = offsets
    }

    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }
        let offset = offsets.isEmpty ? 0 : offsets.removeFirst()
        return time(offset)
    }
}

private func time(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_700_000_000 + seconds)
}

@Suite("Stream preflight")
struct StreamPreflightTests {
    private func makePreflight(
        outcomes: [Result<Int, URLError>],
        headers: [String: String] = ["Content-Length": "2"],
        clock: [TimeInterval] = [],
        maximumRequests: Int = 5
    ) -> (StreamPreflight, StubResponses, RecordedSleep) {
        let responses = StubResponses(outcomes)
        let sleeps = RecordedSleep()
        let times = Clock(clock)
        let preflight = StreamPreflight(
            http: StubHTTP(responses: responses, headers: headers),
            userAgent: "test-agent",
            policy: PreflightPolicy(maximumRequests: maximumRequests),
            sleep: { await sleeps.sleep($0) },
            now: { times.next() }
        )
        return (preflight, responses, sleeps)
    }

    @Test("a 206 on the first request is ready")
    func immediateReady() async {
        let (preflight, responses, sleeps) = makePreflight(outcomes: [.success(206)])
        let result = await preflight.waitUntilReady(url: URL(string: "https://host/track/1")!) { false }

        #expect(result.isReady)
        #expect(result.requestCount == 1)
        #expect(result.lastStatus == 206)
        #expect(sleeps.delays.isEmpty)
        #expect(await responses.requests.count == 1)
        let request = await responses.requests.first
        #expect(request?.value(forHTTPHeaderField: "Range") == StreamPreflight.rangeHeader)
        #expect(request?.value(forHTTPHeaderField: "User-Agent") == "test-agent")
    }

    @Test("an unwarmed answer is retried after a backoff")
    func retriesUntilReady() async {
        let (preflight, responses, sleeps) = makePreflight(
            outcomes: [.success(503), .failure(URLError(.timedOut)), .success(200)],
            headers: ["Content-Length": "1000"]
        )
        let result = await preflight.waitUntilReady(url: URL(string: "https://host/track/1")!) { false }

        #expect(result.isReady)
        #expect(result.requestCount == 3)
        #expect(result.lastStatus == 200)
        #expect(sleeps.delays == [0.4, 0.8])
        #expect(await responses.requests.count == 3)
    }

    @Test("the ladder stops at five requests")
    func requestCap() async {
        let (preflight, responses, sleeps) = makePreflight(
            outcomes: [.success(503), .success(503), .success(503), .success(503), .success(503), .success(206)]
        )
        let result = await preflight.waitUntilReady(url: URL(string: "https://host/track/1")!) { false }

        #expect(!result.isReady)
        #expect(result.requestCount == 5)
        #expect(result.lastStatus == 503)
        #expect(sleeps.delays == [0.4, 0.8, 1.6, 3.2])
        #expect(await responses.requests.count == 5)
    }

    @Test("a cancelled attempt sends no request")
    func cancelledBeforeStart() async {
        let (preflight, responses, _) = makePreflight(outcomes: [.success(206)])
        let result = await preflight.waitUntilReady(url: URL(string: "https://host/track/1")!) { true }

        #expect(!result.isReady)
        #expect(result.requestCount == 0)
        #expect(await responses.requests.isEmpty)
    }

    @Test("an answer with no length is not usable")
    func noLength() async {
        let (preflight, _, _) = makePreflight(outcomes: [.success(200)], headers: [:])
        let result = await preflight.waitUntilReady(url: URL(string: "https://host/track/1")!) { false }

        #expect(!result.isReady)
        #expect(result.lastStatus == 200)
    }

    @Test("a redirect status is not usable")
    func redirectIsCold() async {
        let (preflight, _, _) = makePreflight(outcomes: [.success(302)], headers: ["Content-Length": "2"])
        let result = await preflight.waitUntilReady(url: URL(string: "https://host/track/1")!) { false }

        #expect(!result.isReady)
    }

    @Test("a delay that would pass the budget is not taken")
    func budgetStopsTheLadder() async {
        // The third backoff (1.6 s) is reached at 8.2 s of wall time, past the budget.
        let (preflight, _, sleeps) = makePreflight(
            outcomes: [.success(503), .success(503), .success(503)],
            clock: [0, 3, 6.7, 8.1]
        )
        let result = await preflight.waitUntilReady(url: URL(string: "https://host/track/1")!) { false }

        #expect(!result.isReady)
        #expect(result.requestCount == 3)
        #expect(sleeps.delays == [0.4, 0.8])
    }

    @Test("the policy allows at most five requests inside eight seconds")
    func policy() {
        let policy = PreflightPolicy.standard
        #expect(policy.maximumRequests == 5)
        #expect(policy.delayBeforeRetry(afterRequests: 1, elapsed: 0) == 0.4)
        #expect(policy.delayBeforeRetry(afterRequests: 4, elapsed: 2.8) == 3.2)
        #expect(policy.delayBeforeRetry(afterRequests: 5, elapsed: 6) == nil)
        #expect(policy.delayBeforeRetry(afterRequests: 3, elapsed: 7.5) == nil)
    }
}
