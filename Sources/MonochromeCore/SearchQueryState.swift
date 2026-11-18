// SearchQueryState.swift: the pure search state machine and its skeleton timing.
import Foundation

/// One catalog answer: songs, albums and artists from the same query.
public struct SearchPayload: Equatable, Sendable {
    public var tracks: [Track]
    public var releases: [RemoteRelease]
    public var artists: [RemoteArtist]

    public init(tracks: [Track] = [], releases: [RemoteRelease] = [], artists: [RemoteArtist] = []) {
        self.tracks = tracks
        self.releases = releases
        self.artists = artists
    }

    public var isEmpty: Bool {
        tracks.isEmpty && releases.isEmpty && artists.isEmpty
    }
}

/// What the search screen is doing. Only `empty` may show "No results".
public enum SearchPhase: Equatable, Sendable {
    case idle
    /// Typed, waiting for the pause before the request goes out.
    case typing(String)
    case loading(String)
    case results(String, SearchPayload)
    case empty(String)
    case failed(String, String)
}

/// Reduces query changes, request starts and answers. An answer for a query the
/// listener has already moved past is dropped, so a slow response never
/// replaces a newer one.
public struct SearchQueryState: Equatable, Sendable {
    public private(set) var phase: SearchPhase = .idle
    /// The query of the current phase; nil when idle.
    public private(set) var activeQuery: String?
    /// The last accepted non-empty answer. Kept while a newer query is on its
    /// way, so the screen does not blank out between keystrokes.
    public private(set) var lastPayload: SearchPayload?
    /// Shortest query the catalog is asked about.
    public static let minimumQueryLength = 2

    public init() {}

    public var isWaiting: Bool {
        switch phase {
        case .typing, .loading: true
        case .idle, .results, .empty, .failed: false
        }
    }

    public var showsNoResults: Bool {
        if case .empty = phase { return true }
        return false
    }

    public var failureMessage: String? {
        if case .failed(_, let message) = phase { return message }
        return nil
    }

    public var payload: SearchPayload? {
        if case .results(_, let payload) = phase { return payload }
        return nil
    }

    /// The query that produced what is on screen, for the filters and sections.
    public var resultsQuery: String? {
        if case .results(let query, _) = phase { return query }
        return nil
    }

    /// What the list shows: the finished answer, the last one while the next
    /// query is loading, or nothing when the query has no answer.
    public var shownPayload: SearchPayload {
        switch phase {
        case .results(_, let payload): payload
        case .typing, .loading: lastPayload ?? SearchPayload()
        case .idle, .empty, .failed: SearchPayload()
        }
    }

    public mutating func queryChanged(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= Self.minimumQueryLength else {
            activeQuery = nil
            lastPayload = nil
            phase = .idle
            return
        }
        guard text != activeQuery else { return }
        activeQuery = text
        phase = .typing(text)
    }

    public mutating func requestStarted(for query: String) {
        guard query == activeQuery else { return }
        phase = .loading(query)
    }

    public mutating func received(_ payload: SearchPayload, for query: String) {
        guard query == activeQuery else { return }
        lastPayload = payload.isEmpty ? nil : payload
        phase = payload.isEmpty ? .empty(query) : .results(query, payload)
    }

    public mutating func failed(_ message: String, for query: String) {
        guard query == activeQuery else { return }
        phase = .failed(query, message)
    }

    public mutating func clear() {
        activeQuery = nil
        lastPayload = nil
        phase = .idle
    }
}

/// Skeleton visibility: appears only after the grace period and, once shown,
/// stays for the minimum so a quick answer never flashes rows. All decisions
/// take the current date, so the tests run on a fake clock.
public struct SearchSkeletonState: Equatable, Sendable {
    public private(set) var waitingSince: Date?
    public private(set) var visibleSince: Date?

    public init() {}

    public var isVisible: Bool { visibleSince != nil }

    public mutating func update(waiting: Bool, at now: Date) {
        if waiting {
            if waitingSince == nil { waitingSince = now }
            if visibleSince == nil,
               let start = waitingSince,
               now.timeIntervalSince(start) >= Self.seconds(LayoutSpec.searchSkeletonGraceMs) - Self.epsilon {
                visibleSince = now
            }
            return
        }
        waitingSince = nil
        guard let shown = visibleSince else { return }
        if now.timeIntervalSince(shown) >= Self.seconds(LayoutSpec.searchSkeletonMinVisibleMs) - Self.epsilon {
            visibleSince = nil
        }
    }

    /// Seconds until the next automatic change, or nil when nothing will change
    /// without another `update` call.
    public func nextChangeDelay(at now: Date) -> TimeInterval? {
        if let start = waitingSince, visibleSince == nil {
            return Self.remaining(Self.seconds(LayoutSpec.searchSkeletonGraceMs) - now.timeIntervalSince(start))
        }
        if waitingSince == nil, let shown = visibleSince {
            return Self.remaining(Self.seconds(LayoutSpec.searchSkeletonMinVisibleMs) - now.timeIntervalSince(shown))
        }
        return nil
    }

    /// A millisecond compared as a double can land just below its own value.
    private static let epsilon: TimeInterval = 0.0005

    private static func seconds(_ milliseconds: Int) -> TimeInterval {
        Double(milliseconds) / 1000
    }

    private static func remaining(_ value: TimeInterval) -> TimeInterval {
        value <= epsilon ? 0 : value
    }
}
