// LyricsService.swift: cache-first lyrics loads with one retry and offline fallback.
import Foundation

public enum LyricsLoadError: Error, Equatable, Sendable {
    case offline
    case rateLimited(retryAfter: TimeInterval?)
    case unavailable
}

extension LyricsLoadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .offline:
            "Lyrics are not available offline."
        case .rateLimited(let retryAfter):
            if let retryAfter, retryAfter > 0 {
                "The lyrics service is busy. Try again in \(Int(retryAfter.rounded(.up))) seconds."
            } else {
                "The lyrics service is busy. Try again later."
            }
        case .unavailable:
            "Lyrics could not be loaded. Try again."
        }
    }
}

public actor LyricsService {
    private let provider: any LyricsProviding
    private let cache: LyricsCache
    private let now: @Sendable () -> Date
    private let retryDelay: Duration
    private let log: (@Sendable (String) -> Void)?

    public init(
        provider: any LyricsProviding,
        cache: LyricsCache,
        now: @escaping @Sendable () -> Date = { .now },
        retryDelay: Duration = .milliseconds(250),
        log: (@Sendable (String) -> Void)? = nil
    ) {
        self.provider = provider
        self.cache = cache
        self.now = now
        self.retryDelay = retryDelay
        self.log = log
    }

    public var sourceName: String { provider.sourceName }

    /// Fresh cache, then the network, then a stale cache when the network fails.
    /// `refreshing` skips the fresh entry so Retry can ask the provider again.
    public func load(_ query: LyricsQuery, refreshing: Bool = false) async throws -> LyricsResult {
        guard query.isQueryable else { throw LyricsLoadError.unavailable }
        let providerName = provider.sourceName

        if !refreshing,
           let cached = await cache.result(for: query, provider: providerName, now: now()) {
            log?("lyrics cache hit track=\(query.trackID) state=\(Self.stateLabel(cached))")
            return cached
        }

        log?("lyrics request track=\(query.trackID) refreshing=\(refreshing)")
        do {
            let result = try await fetchWithRetry(query)
            try Task.checkCancellation()
            await cache.store(result, for: query, provider: providerName, now: now())
            log?("lyrics result track=\(query.trackID) state=\(Self.stateLabel(result))")
            return result
        } catch is CancellationError {
            log?("lyrics cancelled track=\(query.trackID)")
            throw CancellationError()
        } catch let error as LyricsProviderError {
            if let stale = await cache.result(
                for: query,
                provider: providerName,
                now: now(),
                allowExpired: true
            ) {
                log?("lyrics cache stale track=\(query.trackID) state=\(Self.stateLabel(stale)) reason=\(error)")
                return stale
            }
            log?("lyrics error track=\(query.trackID) reason=\(error)")
            switch error {
            case .offline:
                throw LyricsLoadError.offline
            case .transient:
                throw LyricsLoadError.unavailable
            case .rateLimited(let retryAfter):
                throw LyricsLoadError.rateLimited(retryAfter: retryAfter)
            default:
                throw LyricsLoadError.unavailable
            }
        }
    }

    private func fetchWithRetry(_ query: LyricsQuery) async throws -> LyricsResult {
        do {
            return try await provider.fetch(query)
        } catch let error as LyricsProviderError where error.shouldRetry {
            log?("lyrics retry track=\(query.trackID) reason=\(error)")
            try await Task.sleep(for: retryDelay)
            try Task.checkCancellation()
            return try await provider.fetch(query)
        }
    }

    private static func stateLabel(_ result: LyricsResult) -> String {
        switch result.content {
        case .synced(let lines): "synced lines=\(lines.count)"
        case .plain(let text): "plain chars=\(text.count)"
        case .instrumental: "instrumental"
        case .notFound: "notFound"
        }
    }
}

private extension LyricsProviderError {
    /// One retry only, and never for a rate limit or a rejected request.
    var shouldRetry: Bool {
        switch self {
        case .transient, .server: true
        default: false
        }
    }
}
