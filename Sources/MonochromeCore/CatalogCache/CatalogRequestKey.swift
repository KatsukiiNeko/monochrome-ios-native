// CatalogRequestKey.swift: the normalized identity and lifetime of a catalog request.
import Foundation

public enum CatalogCacheKind: String, Codable, Sendable, Equatable {
    case search
    case detail

    /// Search results go stale quickly; album and artist pages change rarely.
    public var timeToLive: TimeInterval {
        switch self {
        case .search: 10 * 60
        case .detail: 6 * 60 * 60
        }
    }
}

/// A cache key ignores query order, host case, default ports and fragments, so
/// the same search always maps to one entry. `nil` means this request must never
/// be cached: stream URLs can expire and are not catalog data.
public struct CatalogRequestKey: Hashable, Sendable {
    public let value: String
    public let kind: CatalogCacheKind

    public init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased(),
              !host.isEmpty else { return nil }

        let path = components.path
        // Stream resolution lives under /track/ and is handled locally, but a
        // request that reaches it must still bypass the cache.
        guard !path.contains("/track/") else { return nil }

        components.scheme = scheme
        components.host = host
        components.fragment = nil
        if (scheme == "https" && components.port == 443)
            || (scheme == "http" && components.port == 80) {
            components.port = nil
        }
        components.queryItems = (components.queryItems ?? []).sorted { left, right in
            if left.name != right.name { return left.name < right.name }
            return (left.value ?? "") < (right.value ?? "")
        }
        guard let normalized = components.url?.absoluteString else { return nil }

        self.value = normalized
        self.kind = path.contains("/search/") ? .search : .detail
    }
}
