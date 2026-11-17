// PlaylistMatcher.swift: score catalog candidates for an imported entry.
// Auto-accept at or above the threshold; otherwise keep the top few for review.
import Foundation

public struct PlaylistMatch: Equatable, Sendable, Identifiable {
    public var id: String { candidate.id }
    public var candidate: Track
    /// 0...1 combined title/artist/album/duration similarity.
    public var score: Double

    public init(candidate: Track, score: Double) {
        self.candidate = candidate
        self.score = score
    }
}

public struct PlaylistMatchOutcome: Equatable, Sendable {
    public var entry: PlaylistImportEntry
    /// Auto-accepted when the best score clears `PlaylistMatcher.autoAcceptScore`.
    public var accepted: PlaylistMatch?
    /// Up to three best candidates when the entry needs a human choice.
    public var reviewCandidates: [PlaylistMatch]

    public init(entry: PlaylistImportEntry, accepted: PlaylistMatch?, reviewCandidates: [PlaylistMatch]) {
        self.entry = entry
        self.accepted = accepted
        self.reviewCandidates = reviewCandidates
    }
}

public enum PlaylistMatcher {
    public static let autoAcceptScore = 0.85
    public static let reviewCandidateCount = 3
    /// Duration disagreement beyond this many seconds is penalized.
    public static let durationTolerance = 4.0

    /// Normalizes for matching: lowercase, letters/numbers/space only, collapsed.
    static func normalized(_ raw: String) -> String {
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var kept = ""
        var lastWasSpace = false
        for character in folded {
            if character.isLetter || character.isNumber {
                kept.append(character)
                lastWasSpace = false
            } else if !lastWasSpace {
                kept.append(" ")
                lastWasSpace = true
            }
        }
        return kept.trimmingCharacters(in: .whitespaces)
    }

    /// Sørensen–Dice on character bigrams, 0...1. Empty inputs score 0.
    static func similarity(_ a: String, _ b: String) -> Double {
        let left = normalized(a), right = normalized(b)
        guard left.count > 1, right.count > 1 else {
            return left == right && !left.isEmpty ? 1.0 : 0.0
        }
        func bigrams(_ text: String) -> [String] {
            let characters = Array(text)
            return (0..<characters.count - 1).map { String(characters[$0...$0 + 1]) }
        }
        let leftGrams = bigrams(left), rightGrams = bigrams(right)
        var counts: [String: Int] = [:]
        for gram in leftGrams { counts[gram, default: 0] += 1 }
        var shared = 0
        for gram in rightGrams where counts[gram, default: 0] > 0 {
            counts[gram]! -= 1
            shared += 1
        }
        return Double(2 * shared) / Double(leftGrams.count + rightGrams.count)
    }

    /// Weights: title dominates, artist second, album as tiebreak, duration
    /// subtracts when the two are known and far apart.
    public static func score(entry: PlaylistImportEntry, candidate: Track) -> Double {
        let titleScore = similarity(entry.title, candidate.title)
        let artistScore = entry.artist.isEmpty
            ? 0.5 // no artist claim: do not punish, but do not reward either
            : similarity(entry.artist, candidate.displayArtist)
        let albumScore: Double = {
            guard let album = entry.album, !album.isEmpty else { return 0.5 }
            return similarity(album, candidate.displayAlbum)
        }()
        var durationPenalty = 0.0
        if let entryDuration = entry.durationSeconds, let candidateDuration = candidate.durationSeconds {
            let drift = abs(entryDuration - candidateDuration)
            if drift > durationTolerance {
                // Up to 0.5 off for a full-minute difference.
                durationPenalty = min(0.5, (drift - durationTolerance) / 120.0)
            }
        }
        let weighted = 0.55 * titleScore + 0.30 * artistScore + 0.15 * albumScore
        return max(0.0, weighted - durationPenalty)
    }

    /// The query a catalog search runs with: artist and title together.
    public static func searchQuery(for entry: PlaylistImportEntry) -> String {
        entry.artist.isEmpty ? entry.title : "\(entry.artist) \(entry.title)"
    }

    /// Ranks one candidate list for one entry. `accepted` requires the threshold.
    public static func match(entry: PlaylistImportEntry, candidates: [Track]) -> PlaylistMatchOutcome {
        let ranked = candidates
            .map { PlaylistMatch(candidate: $0, score: score(entry: entry, candidate: $0)) }
            .sorted { $0.score > $1.score }
        let best = ranked.first
        let accepted = (best?.score ?? 0) >= autoAcceptScore ? best : nil
        let review = accepted == nil
            ? Array(ranked.prefix(reviewCandidateCount).filter { $0.score > 0.2 })
            : []
        return PlaylistMatchOutcome(entry: entry, accepted: accepted, reviewCandidates: review)
    }
}
