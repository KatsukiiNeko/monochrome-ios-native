// HomeStations.swift: the artist seeds the home station row offers.
import Foundation

/// Radio seeds for Home, taken from what the listener already keeps: favorites
/// first, then recent plays. A name appears once, and an empty artist is never
/// a seed because a station needs something to search for.
public enum HomeStations {
    public static func artists(favorites: [Track], recents: [Track], limit: Int = 4) -> [String] {
        guard limit > 0 else { return [] }
        var seen: Set<String> = []
        var names: [String] = []
        for track in favorites + recents {
            let name = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            guard seen.insert(key).inserted else { continue }
            names.append(name)
            if names.count == limit { break }
        }
        return names
    }
}
