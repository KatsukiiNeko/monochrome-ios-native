// QuickAccess.swift: merge recents and favorites into a de-duplicated grid.
import Foundation

public enum QuickAccess {
    /// Recents first, then favorites that are not already present.
    public static func merge(
        recents: [Track],
        favorites: [Track],
        limit: Int = 6
    ) -> [Track] {
        guard limit > 0 else { return [] }
        var seen = Set<String>()
        var result: [Track] = []
        for track in recents + favorites {
            guard seen.insert(track.id).inserted else { continue }
            result.append(track)
            if result.count == limit { break }
        }
        return result
    }
}
