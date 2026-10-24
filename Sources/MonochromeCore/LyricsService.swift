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

    public init(
        provider: any LyricsProviding,
        cache: LyricsCache,
        now: @escaping @Sendable () -> Date = { .now },
        retryDelay: Duration = .milliseconds(250)
    ) {
        self.provider = provider
        self.cache = cache
        self.now = now
        self.retryDelay = retryDelay
    }

    public var sourceName: String { provider.sourceName }

    /// Fresh cache, then the network, then a stale cache when the network fails.
    public func load(_ query: LyricsQuery) async throws -> LyricsResult {
        guard query.isQueryable else { throw LyricsLoadError.unavailable }
        let providerName = provider.sourceName

        if let cached = await cache.result(for: query, provider: providerName, now: now()) {
            return cached
        }

        do {
            let result = try await fetchWithRetry(query)
            try Task.checkCancellation()
            await cache.store(result, for: query, provider: providerName, now: now())
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LyricsProviderError {
            if let stale = await cache.result(
                for: query,
                provider: providerName,
                now: now(),
                allowExpired: true
            ) {
                return stale
            }
            switch error {
            case .offline, .transient:
                throw LyricsLoadError.offline
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
            try await Task.sleep(for: retryDelay)
            try Task.checkCancellation()
            return try await provider.fetch(query)
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
