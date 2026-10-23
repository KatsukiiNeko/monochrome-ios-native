// SearchResults.swift: result types that exist and the section partitioning for a filter.
import Foundation

public enum SearchResultKind: String, CaseIterable, Identifiable, Sendable {
    case all
    case songs
    case albums
    case artists

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .songs: "Songs"
        case .albums: "Albums"
        case .artists: "Artists"
        }
    }
}

public struct SearchResultSections: Equatable, Sendable {
    public var tracks: [Track]
    public var releases: [RemoteRelease]
    public var artists: [RemoteArtist]

    public init(
        tracks: [Track] = [],
        releases: [RemoteRelease] = [],
        artists: [RemoteArtist] = []
    ) {
        self.tracks = tracks
        self.releases = releases
        self.artists = artists
    }
}

public enum SearchResults {
    /// All is always offered when anything came back; the rest only when present.
    public static func availableKinds(
        hasTracks: Bool,
        hasReleases: Bool,
        hasArtists: Bool
    ) -> [SearchResultKind] {
        guard hasTracks || hasReleases || hasArtists else { return [] }
        var kinds: [SearchResultKind] = [.all]
        if hasTracks { kinds.append(.songs) }
        if hasReleases { kinds.append(.albums) }
        if hasArtists { kinds.append(.artists) }
        return kinds
    }

    public static func apply(
        _ kind: SearchResultKind,
        tracks: [Track],
        releases: [RemoteRelease],
        artists: [RemoteArtist]
    ) -> SearchResultSections {
        switch kind {
        case .all:
            SearchResultSections(tracks: tracks, releases: releases, artists: artists)
        case .songs:
            SearchResultSections(tracks: tracks)
        case .albums:
            SearchResultSections(releases: releases)
        case .artists:
            SearchResultSections(artists: artists)
        }
    }
}
