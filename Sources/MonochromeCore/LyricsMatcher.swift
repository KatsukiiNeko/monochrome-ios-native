// LyricsMatcher.swift: conservative comparison of provider candidates to a track.
import Foundation

/// The fields a provider record contributes to matching. Lyrics text is not kept here.
public struct LyricsCandidate: Equatable, Sendable {
    public var trackName: String
    public var artistName: String
    public var albumName: String?
    public var duration: TimeInterval?
    public var hasSyncedLyrics: Bool
    public var hasPlainLyrics: Bool
    public var instrumental: Bool

    public init(
        trackName: String,
        artistName: String,
        albumName: String? = nil,
        duration: TimeInterval? = nil,
        hasSyncedLyrics: Bool = false,
        hasPlainLyrics: Bool = false,
        instrumental: Bool = false
    ) {
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.duration = duration
        self.hasSyncedLyrics = hasSyncedLyrics
        self.hasPlainLyrics = hasPlainLyrics
        self.instrumental = instrumental
    }
}

public enum LyricsMatcher {
    /// A wrong lyric is worse than none: anything below this stays notFound.
    public static let minimumScore = 0.72
    /// Provider durations vary by a second or two between releases.
    public static let durationTolerance: TimeInterval = 3

    public static func bestMatch(
        for query: LyricsQuery,
        in candidates: [LyricsCandidate]
    ) -> LyricsCandidate? {
        guard query.isQueryable else { return nil }

        let scored = candidates.compactMap { candidate -> (LyricsCandidate, Double)? in
            guard let score = score(query: query, candidate: candidate) else { return nil }
            return (candidate, score)
        }

        return scored.max { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            let leftRank = contentRank(lhs.0)
            let rightRank = contentRank(rhs.0)
            if leftRank != rightRank { return leftRank < rightRank }
            return durationDifference(query, lhs.0) > durationDifference(query, rhs.0)
        }?.0
    }

    /// nil means reject outright. The score is only used to rank acceptable candidates.
    public static func score(query: LyricsQuery, candidate: LyricsCandidate) -> Double? {
        let title = normalized(query.title)
        let artist = normalized(query.artist)
        let candidateTitle = normalized(candidate.trackName)
        let candidateArtist = normalized(candidate.artistName)
        guard !title.isEmpty, !artist.isEmpty,
              !candidateTitle.isEmpty, !candidateArtist.isEmpty
        else { return nil }

        let titleScore = similarity(title, candidateTitle)
        let artistScore = similarity(artist, candidateArtist)
        guard titleScore >= 0.6, artistScore >= 0.5 else { return nil }

        let durationScore: Double
        if let queryDuration = query.duration, let candidateDuration = candidate.duration {
            let difference = abs(queryDuration - candidateDuration)
            guard difference <= durationTolerance else { return nil }
            durationScore = 1
        } else {
            durationScore = 0.5
        }

        let total = 0.60 * titleScore + 0.25 * artistScore + 0.15 * durationScore
        return total >= minimumScore ? total : nil
    }

    /// Comparison-only normalization. The original strings are always what gets displayed.
    public static func normalized(_ text: String) -> String {
        var value = text.precomposedStringWithCanonicalMapping
        value = value.replacingOccurrences(of: "&", with: " and ")
        value = removingVersionBrackets(value)
        value = removingVersionSuffixes(value)
        value = value.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        value = value
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")

        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                scalars.append(" ")
            }
        }
        return String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        if lhs == rhs { return 1 }
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        var score = 0.0
        if lhs.contains(rhs) || rhs.contains(lhs) { score = 0.8 }
        let lhsTokens = Set(lhs.split(separator: " "))
        let rhsTokens = Set(rhs.split(separator: " "))
        let union = lhsTokens.union(rhsTokens)
        if !union.isEmpty {
            let jaccard = Double(lhsTokens.intersection(rhsTokens).count) / Double(union.count)
            score = max(score, jaccard)
        }
        return score
    }

    private static func contentRank(_ candidate: LyricsCandidate) -> Int {
        if candidate.hasSyncedLyrics { return 3 }
        if candidate.hasPlainLyrics { return 2 }
        if candidate.instrumental { return 1 }
        return 0
    }

    private static func durationDifference(_ query: LyricsQuery, _ candidate: LyricsCandidate) -> Double {
        guard let queryDuration = query.duration, let candidateDuration = candidate.duration else {
            return .greatestFiniteMagnitude
        }
        return abs(queryDuration - candidateDuration)
    }

    private static let versionKeywords = [
        "feat", "ft.", "ft ", "featuring", "with ", "remaster", "live",
        "radio edit", "version", "mono", "stereo", "deluxe", "bonus", "from ",
    ]

    private static func removingVersionBrackets(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"[\(\[][^\)\]]*[\)\]]"#) else {
            return text
        }
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let content = String(text[range]).lowercased()
            guard versionKeywords.contains(where: content.contains) else { continue }
            if let swiftRange = Range(match.range, in: result) {
                result.replaceSubrange(swiftRange, with: "")
            }
        }
        return result
    }

    private static func removingVersionSuffixes(_ text: String) -> String {
        let separators = [" - ", " – ", " — "]
        var value = text
        for separator in separators {
            value = value.replacingOccurrences(of: separator, with: " - ")
        }
        var parts = value.components(separatedBy: " - ")
        while parts.count > 1 {
            let last = parts[parts.count - 1].lowercased()
            guard versionKeywords.contains(where: last.contains) else { break }
            parts.removeLast()
        }
        return parts.joined(separator: " ")
    }
}
