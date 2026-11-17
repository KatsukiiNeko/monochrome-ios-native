// CachedHTTPClient.swift: GET responses are cached; stale entries are served while
// a background request revalidates them. Errors are never stored.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class CachedHTTPClient: HTTPClient, @unchecked Sendable {
    private let upstream: any HTTPClient
    private let cache: CatalogResponseCache
    private let now: @Sendable () -> Date
    private let log: (@Sendable (String) -> Void)?
    /// Prevents one background refresh per stale read when several requests overlap.
    private let gate = RefreshGate()

    public init(
        upstream: any HTTPClient,
        cache: CatalogResponseCache,
        now: @escaping @Sendable () -> Date = { .now },
        log: (@Sendable (String) -> Void)? = nil
    ) {
        self.upstream = upstream
        self.cache = cache
        self.now = now
        self.log = log
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.httpMethod == nil || request.httpMethod == "GET",
              let url = request.url,
              let key = CatalogRequestKey(url: url) else {
            return try await upstream.data(for: request)
        }

        if let cached = await cache.entry(for: key) {
            if cached.isFresh {
                log?("catalog cache hit key=\(key.value)")
                return try makeResponse(cached.response, url: url)
            }
            // Stale content is still browsable, so it is served at once; the
            // refresh only replaces it for the next visit.
            log?("catalog cache stale key=\(key.value)")
            revalidate(request: request, key: key)
            return try makeResponse(cached.response, url: url)
        }

        log?("catalog cache miss key=\(key.value)")
        let (data, response) = try await upstream.data(for: request)
        // A failed request must not hide a later healthy answer, so only success
        // is stored. This also means errors are never served for any length of time.
        if (200..<300).contains(response.statusCode) {
            await cache.store(data: data, statusCode: response.statusCode, for: key)
        }
        return (data, response)
    }

    private func revalidate(request: URLRequest, key: CatalogRequestKey) {
        let upstream = self.upstream
        let cache = self.cache
        let gate = self.gate
        let log = self.log
        Task {
            guard await gate.begin(key.value) else { return }
            defer { Task { await gate.end(key.value) } }
            do {
                let (data, response) = try await upstream.data(for: request)
                guard (200..<300).contains(response.statusCode) else {
                    log?("catalog revalidate failed status=\(response.statusCode)")
                    return
                }
                await cache.store(data: data, statusCode: response.statusCode, for: key)
                log?("catalog revalidate stored key=\(key.value)")
            } catch {
                // Offline: the stale entry stays and keeps the catalog browsable.
                log?("catalog revalidate failed reason=\(error.localizedDescription)")
            }
        }
    }

    private func makeResponse(_ cached: CachedCatalogResponse, url: URL) throws -> (Data, HTTPURLResponse) {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: cached.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            throw HTTPClientError.invalidResponse
        }
        return (cached.data, response)
    }
}

private actor RefreshGate {
    private var keys: Set<String> = []

    func begin(_ key: String) -> Bool {
        keys.insert(key).inserted
    }

    func end(_ key: String) {
        keys.remove(key)
    }
}
