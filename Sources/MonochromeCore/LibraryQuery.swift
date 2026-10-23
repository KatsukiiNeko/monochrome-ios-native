// LibraryQuery.swift: filter and sort the library rows without touching the view.
import Foundation

public enum LibraryFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case favorites
    case local

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .favorites: "Favorites"
        case .local: "Local files"
        }
    }
}

public enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case recent
    case title
    case artist

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recent: "Recently added"
        case .title: "Title"
        case .artist: "Artist"
        }
    }
}

public enum LibraryQuery {
    public static func rows(
        tracks: [Track],
        favorites: [Track],
        filter: LibraryFilter,
        sort: LibrarySort
    ) -> [Track] {
        let selected: [Track]
        switch filter {
        case .all:
            selected = merged(tracks: tracks, favorites: favorites)
        case .favorites:
            selected = favorites
        case .local:
            selected = tracks
        }
        return sorted(selected, by: sort)
    }

    private static func merged(tracks: [Track], favorites: [Track]) -> [Track] {
        var seen = Set<String>()
        var result: [Track] = []
        for track in tracks + favorites {
            guard seen.insert(track.id).inserted else { continue }
            result.append(track)
        }
        return result
    }

    private static func sorted(_ tracks: [Track], by sort: LibrarySort) -> [Track] {
        switch sort {
        case .recent:
            tracks.sorted {
                if $0.importedAt != $1.importedAt { return $0.importedAt > $1.importedAt }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .title:
            tracks.sorted {
                let order = $0.title.localizedCaseInsensitiveCompare($1.title)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
        case .artist:
            tracks.sorted {
                let left = $0.displayArtist.localizedCaseInsensitiveCompare($1.displayArtist)
                if left != .orderedSame { return left == .orderedAscending }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        }
    }
}
