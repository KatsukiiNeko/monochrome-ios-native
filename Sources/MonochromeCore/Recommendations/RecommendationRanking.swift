// RecommendationRanking.swift: score candidates, keep the list varied and
// explain every pick.
import Foundation

/// A recommendation with the reason it was made.
public struct Recommendation: Equatable, Sendable, Identifiable {
    public var id: String { track.id }
    public var track: Track
    /// Plain words: "Because you play Daft Punk".
    public var reason: String
    public var score: Double

    public init(track: Track, reason: String, score: Double) {
        self.track = track
        self.reason = reason
        self.score = score
    }
}

public enum RecommendationRanker {
    /// How much each signal counts in the final score.
    public static let artistWeight = 0.65
    public static let albumWeight = 0.15
    public static let sourceWeight = 0.15
    /// At most two tracks per artist in the first ten.
    public static let diversityLimit = 2
    public static let diversityWindow = 10
    /// Extra plays of a track lower its score a little.
    public static let repeatPenalty = 0.05
    /// A track the listener already owns is less of a discovery.
    public static let knownTrackPenalty = 0.1

    /// Ranks catalog candidates for the listener.
    /// - Parameters:
    ///   - candidates: tracks found through the allowed search route.
    ///   - profile: the listener's taste.
    ///   - library: tracks the listener already has, used for the repeat penalty.
    public static func rank(
        candidates: [Track],
        profile: TasteProfile,
        library: [Track] = [],
        limit: Int = 20
    ) -> [Recommendation] {
        let libraryKeys = Set(library.map(\.sourceKey))
        let scored = candidates.map { track -> Recommendation in
            let artistScore = profile.artistScore(track.artist)
            let albumScore = profile.albumScore(track.album)
            // Without a similar-data route, a candidate's similarity to the
            // taste comes from matching a top artist or a top album.
            let sourceScore = profile.topArtists.contains(track.artist.lowercased()) ? 1.0
                : (profile.topAlbums.contains(track.album.lowercased()) ? 0.5 : 0)
            let plays = profile.playCounts[track.sourceKey] ?? 0
            let penalty = repeatPenalty * Double(max(0, plays - 1))
                + (libraryKeys.contains(track.sourceKey) ? knownTrackPenalty : 0)
            let negativeTrack = min(0, profile.trackScore(track.sourceKey))
            let negativeArtist = min(0, artistScore)

            var score = artistWeight * artistScore
                + albumWeight * albumScore
                + sourceWeight * sourceScore
                - penalty
                + negativeTrack
                + negativeArtist
            score = max(0, score)
            return Recommendation(
                track: track,
                reason: reason(for: track, profile: profile),
                score: score
            )
        }

        let best = scored
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
        return diversify(best, limit: limit)
    }

    /// Keeps the list varied: no artist takes more than two slots in the
    /// first ten while the pool still has enough artists. A pool with only a
    /// couple of artists keeps its tracks instead of coming up short.
    static func diversify(_ recommendations: [Recommendation], limit: Int) -> [Recommendation] {
        var perArtist: [String: Int] = [:]
        var result: [Recommendation] = []
        var overflow: [Recommendation] = []
        for recommendation in recommendations {
            let artist = recommendation.track.artist.lowercased()
            let count = perArtist[artist] ?? 0
            if result.count < diversityWindow {
                if count < diversityLimit {
                    perArtist[artist] = count + 1
                    result.append(recommendation)
                } else {
                    overflow.append(recommendation)
                }
            } else {
                perArtist[artist] = count + 1
                result.append(recommendation)
            }
            if result.count >= limit { break }
        }
        // The held-back tracks follow the varied window.
        for recommendation in overflow where result.count < limit {
            result.append(recommendation)
        }
        return Array(result.prefix(limit))
    }

    /// "Because you play <artist>", or a note when the artist is unknown.
    public static func reason(for track: Track, profile: TasteProfile) -> String {
        let artist = track.artist.lowercased()
        if let liked = profile.topArtists.first(where: { $0 == artist }) {
            return "Because you play \(capitalized(liked))"
        }
        if let album = profile.topAlbums.first(where: { $0 == track.album.lowercased() }) {
            return "Because you play \(capitalized(album))"
        }
        return "Picked for you"
    }

    private static func capitalized(_ raw: String) -> String {
        guard let first = raw.first else { return raw }
        return String(first).uppercased() + raw.dropFirst()
    }
}
