// StreamPreflight.swift: one ranged request before a stream URL reaches AVPlayer.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The bounded retry ladder for a preflight. A tap may send at most five
/// ranged requests inside eight seconds, with the delays below between them.
public struct PreflightPolicy: Sendable, Equatable {
    public static let standard = PreflightPolicy()

    public let maximumRequests: Int
    public let totalBudget: TimeInterval
    public let backoff: [TimeInterval]

    public init(
        maximumRequests: Int = 5,
        totalBudget: TimeInterval = 8,
        backoff: [TimeInterval] = [0.4, 0.8, 1.6, 3.2]
    ) {
        self.maximumRequests = max(1, maximumRequests)
        self.totalBudget = totalBudget
        self.backoff = backoff
    }

    /// Delay before the next request, or nil when another may not start: either
    /// the request cap is reached or the delay would pass the total budget.
    public func delayBeforeRetry(afterRequests requests: Int, elapsed: TimeInterval) -> TimeInterval? {
        guard requests >= 1, requests < maximumRequests, !backoff.isEmpty else { return nil }
        let delay = backoff[min(requests - 1, backoff.count - 1)]
        guard elapsed + delay < totalBudget else { return nil }
        return delay
    }
}

/// A flag a request loop can read from any thread; a newer load cancels an
/// older preflight so a skipped tap does not keep sending requests.
public final class AttemptCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

public struct PreflightResult: Equatable, Sendable {
    public var isReady: Bool
    public var requestCount: Int
    public var elapsedMs: Int
    public var lastStatus: Int?

    public init(isReady: Bool, requestCount: Int, elapsedMs: Int, lastStatus: Int? = nil) {
        self.isReady = isReady
        self.requestCount = requestCount
        self.elapsedMs = elapsedMs
        self.lastStatus = lastStatus
    }
}

/// What the player needs from a preflight; faked in host tests.
public protocol StreamPreflighting: Sendable {
    func waitUntilReady(url: URL, isCancelled: @Sendable () -> Bool) async -> PreflightResult
}

/// Sends `Range: bytes=0-1` with the app identity and waits until the origin
/// answers like a progressive file: 200 or 206 with a usable length.
public struct StreamPreflight: StreamPreflighting {
    public static let rangeHeader = "bytes=0-1"
    /// The origin answers a cold ranged request in 2-13 s (measured 2026-11-19),
    /// so a shorter timeout would cut off a healthy warm-up.
    public static let requestTimeout: TimeInterval = 10

    private let http: any HTTPClient
    private let userAgent: String
    private let policy: PreflightPolicy
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let now: @Sendable () -> Date

    public init(
        http: any HTTPClient,
        userAgent: String,
        policy: PreflightPolicy = .standard,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.http = http
        self.userAgent = userAgent
        self.policy = policy
        self.sleep = sleep
        self.now = now
    }

    public func waitUntilReady(url: URL, isCancelled: @Sendable () -> Bool) async -> PreflightResult {
        let started = now()
        var requests = 0
        var lastStatus: Int?
        while true {
            if isCancelled() {
                return result(false, requests: requests, started: started, status: lastStatus)
            }
            requests += 1
            do {
                var request = URLRequest(url: url)
                request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
                request.setValue(Self.rangeHeader, forHTTPHeaderField: "Range")
                request.timeoutInterval = Self.requestTimeout
                let (_, response) = try await http.data(for: request)
                lastStatus = response.statusCode
                // shortcut: URLSession buffers a whole body, so a 200 would cost the
                // full file; the catalog answers 206 to a range (verified 2026-11-18).
                if Self.isUsable(response) {
                    return result(true, requests: requests, started: started, status: lastStatus)
                }
            } catch {
                lastStatus = nil
            }
            let elapsed = now().timeIntervalSince(started)
            guard let delay = policy.delayBeforeRetry(afterRequests: requests, elapsed: elapsed) else {
                return result(false, requests: requests, started: started, status: lastStatus)
            }
            await sleep(delay)
        }
    }

    /// 200 or 206 with a positive length or a content range. Anything else is
    /// treated as cold, even if AVPlayer might have coped with it.
    static func isUsable(_ response: HTTPURLResponse) -> Bool {
        guard response.statusCode == 200 || response.statusCode == 206 else { return false }
        if let length = response.value(forHTTPHeaderField: "Content-Length"), (Int(length) ?? 0) > 0 {
            return true
        }
        return response.value(forHTTPHeaderField: "Content-Range") != nil
    }

    private func result(_ ready: Bool, requests: Int, started: Date, status: Int?) -> PreflightResult {
        PreflightResult(
            isReady: ready,
            requestCount: requests,
            elapsedMs: max(0, Int((now().timeIntervalSince(started) * 1000).rounded())),
            lastStatus: status
        )
    }
}
