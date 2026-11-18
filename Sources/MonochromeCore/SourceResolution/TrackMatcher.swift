// TrackMatcher.swift: decides whether two tracks are the same recording.
import Foundation

/// How a match was made; stored beside a source link.
public enum MatchMethod: String, Codable, Equatable, Sendable {
    case isrc
    case heuristic
}

public struct TrackMatch: Equatable, Sendable {
    public var confidence: Double
    public var method: MatchMethod

    public init(confidence: Double, method: MatchMethod) {
        self.confidence = confidence
        self.method = method
    }
}

/// Version words that change which recording a title names.
public enum VersionFlag: String, CaseIterable, Equatable, Hashable, Sendable {
    case live
    case remix
    case acoustic
    case instrumental
    case spedUp = "sped up"
    case slowed
    case reverb
    case nightcore
    case cover
    case karaoke
    case eightD = "8d"
    case demo
    case extended
    case radioEdit = "radio edit"
    case edit
    case remaster
    case mono
    case stereo
    case clean
    case explicit

    /// Different hard flags mean a different recording, never a match.
    public var isHard: Bool {
        switch self {
        case .demo, .extended, .radioEdit, .edit, .remaster, .mono, .stereo, .clean, .explicit:
            false
        case .live, .remix, .acoustic, .instrumental, .spedUp, .slowed, .reverb, .nightcore,
             .cover, .karaoke, .eightD:
            true
        }
    }
}

/// Pure comparison of two tracks. The score is weighted title, artist,
/// duration, album and credit agreement, minus a penalty per differing soft
/// version flag. A hard version conflict, a different primary artist, an ISRC
/// mismatch or a duration gap above ten seconds returns nil.
public struct TrackMatcher: Sendable {
    /// Confidence needed before a track is swapped for its counterpart.
    public static let defaultMinimumConfidence = 0.88
    /// Full credit up to this difference, then decay to a reject at the limit.
    public static let durationTolerance = 3.0
    public static let durationRejectGap = 10.0

    public var minimumConfidence: Double

    public init(minimumConfidence: Double = TrackMatcher.defaultMinimumConfidence) {
        self.minimumConfidence = minimumConfidence
    }

    public func match(_ candidate: Track, against reference: Track) -> TrackMatch? {
        if let left = candidate.isrc?.normalizedISRC, let right = reference.isrc?.normalizedISRC {
            return left == right ? TrackMatch(confidence: 1, method: .isrc) : nil
        }
        let a = NormalizedTrack(candidate)
        let b = NormalizedTrack(reference)
        guard let score = Self.score(a, b) else { return nil }
        return TrackMatch(confidence: score, method: .heuristic)
    }

    public func isMatch(_ candidate: Track, _ reference: Track) -> Bool {
        guard let match = match(candidate, against: reference) else { return false }
        return match.confidence >= minimumConfidence
    }

    /// Highest scoring candidate that clears the threshold.
    public func bestMatch(for track: Track, among candidates: [Track]) -> (track: Track, match: TrackMatch)? {
        var best: (track: Track, match: TrackMatch)?
        for candidate in candidates {
            guard let match = match(candidate, against: track) else { continue }
            guard match.confidence >= minimumConfidence else { continue }
            if match.confidence > (best?.match.confidence ?? -1) {
                best = (candidate, match)
            }
        }
        return best
    }
}

// MARK: - Score

extension TrackMatcher {
    static func score(_ a: NormalizedTrack, _ b: NormalizedTrack) -> Double? {
        guard !a.title.isEmpty, !b.title.isEmpty else { return nil }
        let hardA = a.flags.filter(\.isHard)
        let hardB = b.flags.filter(\.isHard)
        guard hardA == hardB else { return nil }
        guard !a.primaryArtist.isEmpty, a.primaryArtist == b.primaryArtist else { return nil }
        // "Part 1" and "Part 2" are different recordings even when every
        // other word agrees.
        let digitsA = a.titleTokens.filter { $0.allSatisfy(\.isNumber) }
        let digitsB = b.titleTokens.filter { $0.allSatisfy(\.isNumber) }
        if !digitsA.isEmpty, !digitsB.isEmpty, digitsA != digitsB { return nil }
        guard let durationScore = durationScore(a.duration, b.duration) else { return nil }

        let titleScore = 0.5 * jaccard(a.titleTokens, b.titleTokens)
            + 0.5 * stringSimilarity(a.title, b.title)
        let artistScore: Double
        if a.artists == b.artists || a.artists.isSubset(of: b.artists) || b.artists.isSubset(of: a.artists) {
            artistScore = 1
        } else {
            artistScore = 0.9
        }
        let albumScore: Double
        if a.album.isEmpty || b.album.isEmpty {
            albumScore = 0.5
        } else {
            albumScore = a.album == b.album ? 1 : 0
        }
        let creditScore = a.extras == b.extras ? 1.0 : 0.25

        var score = 0.45 * titleScore
            + 0.30 * artistScore
            + 0.15 * durationScore
            + 0.05 * albumScore
            + 0.05 * creditScore

        let softA = a.flags.filter { !$0.isHard }
        let softB = b.flags.filter { !$0.isHard }
        score -= 0.08 * Double(softA.symmetricDifference(softB).count)
        return min(max(score, 0), 1)
    }

    /// Nil means the gap is too wide to be the same recording.
    private static func durationScore(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b, a > 0, b > 0 else { return 0.5 }
        let gap = abs(a - b)
        if gap <= durationTolerance { return 1 }
        if gap > durationRejectGap { return nil }
        return 1 - (gap - durationTolerance) / (durationRejectGap - durationTolerance)
    }

    private static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 0.5 }
        let union = a.union(b).count
        guard union > 0 else { return 0.5 }
        return Double(a.intersection(b).count) / Double(union)
    }

    /// 1 for equal strings, falling to 0 as the edit distance reaches the
    /// longer length.
    static func stringSimilarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let left = Array(a)
        let right = Array(b)
        let longest = max(left.count, right.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(editDistance(left, right)) / Double(longest)
    }

    /// Two-row Levenshtein distance.
    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

// MARK: - Normalization

extension TrackMatcher {
    static let noiseWords: Set<String> = [
        "official", "music", "video", "audio", "lyric", "lyrics", "visualizer",
        "hd", "hq", "4k", "mv", "m", "v",
    ]

    static let featMarkers = ["feat.", "feat", "ft.", "ft", "featuring"]

    /// Lowercases, strips diacritics and width, and turns `&` into `and`.
    static func fold(_ text: String) -> String {
        text
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "&", with: " and ")
    }

    static func words(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    /// Split a title into its main part and bracketed or dash segments so the
    /// caller can move flags and credits out of the title.
    static func segments(of text: String) -> (main: [String], segments: [String]) {
        var main: [String] = []
        var segments: [String] = []
        var current = ""
        var depth = 0
        for character in text {
            switch character {
            case "(", "[":
                if depth == 0 {
                    main.append(current)
                    current = ""
                }
                depth += 1
            case ")", "]":
                if depth > 0 {
                    depth -= 1
                    if depth == 0 {
                        segments.append(current)
                        current = ""
                    } else {
                        current.append(character)
                    }
                } else {
                    current.append(character)
                }
            default:
                current.append(character)
            }
        }
        if !current.isEmpty { main.append(current) }

        var titleParts: [String] = []
        for part in main {
            let pieces = part.components(separatedBy: " - ")
            titleParts.append(pieces.first ?? part)
            segments.append(contentsOf: pieces.dropFirst())
        }
        return (titleParts, segments)
    }

    static func versionFlags(in text: String) -> Set<VersionFlag> {
        var found: Set<VersionFlag> = []
        var scanned = " " + fold(text).replacingOccurrences(of: " - ", with: " ") + " "
        // Longest phrasings first so "radio edit" is not read as "edit" too.
        let ordered = VersionFlag.allCases.sorted { $0.rawValue.count > $1.rawValue.count }
        for flag in ordered {
            let phrase = " \(flag.rawValue) "
            guard scanned.contains(phrase) else { continue }
            found.insert(flag)
            scanned = scanned.replacingOccurrences(of: phrase, with: " ")
        }
        return found
    }

    static func isNoise(_ segment: String) -> Bool {
        let tokens = words(segment)
        guard !tokens.isEmpty else { return true }
        return tokens.allSatisfy(noiseWords.contains)
    }

    /// The names after a feat marker, when the segment carries one. The text is
    /// padded so a marker at the start or end still has word boundaries.
    static func credits(in text: String) -> (head: String, names: [String])? {
        let padded = " " + fold(text) + " "
        var earliest: Range<String.Index>?
        for marker in featMarkers {
            guard let range = padded.range(of: " \(marker) ") else { continue }
            if earliest == nil || range.lowerBound < earliest!.lowerBound {
                earliest = range
            }
        }
        guard let earliest else { return nil }
        let head = String(padded[padded.startIndex..<earliest.lowerBound])
        let tail = String(padded[earliest.upperBound...])
        let names = artistNames(tail)
        return names.isEmpty ? nil : (head, names)
    }

    /// Splits a credit list into normalized artist names.
    static func artistNames(_ text: String) -> [String] {
        let separators = [",", " and ", " with ", "+", "/"] + featMarkers.map { " \($0) " }
        var pieces = [fold(text)]
        for separator in separators {
            pieces = pieces.flatMap { $0.components(separatedBy: separator) }
        }
        return pieces
            .map { words($0).joined(separator: " ") }
            .filter { !$0.isEmpty }
    }

    /// Drops punctuation-only differences and collapses whitespace.
    static func cleanTitle(_ text: String) -> String {
        words(fold(text)).joined(separator: " ")
    }

    /// A bare trailing marker such as "HD" is noise; a leading or inner word is
    /// part of the title, so only the end is trimmed.
    static func stripTrailingNoise(_ title: String) -> String {
        var tokens = title.split(separator: " ").map(String.init)
        while let last = tokens.last, noiseWords.contains(last) {
            tokens.removeLast()
        }
        return tokens.joined(separator: " ")
    }
}

/// One side of a comparison, with everything the score needs.
struct NormalizedTrack {
    var title: String
    var titleTokens: Set<String>
    var artists: Set<String>
    var primaryArtist: String
    /// Credits that were moved out of the title or named after the primary.
    var extras: Set<String>
    var flags: Set<VersionFlag>
    var album: String
    var duration: Double?
    var isrc: String?

    init(_ track: Track) {
        let foldedTitle = TrackMatcher.fold(track.title)
        let split = TrackMatcher.segments(of: foldedTitle)
        var flags: Set<VersionFlag> = []
        var extras: Set<String> = []
        var kept: [String] = []

        for segment in split.segments {
            guard !segment.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let segmentFlags = TrackMatcher.versionFlags(in: segment)
            if !segmentFlags.isEmpty {
                flags.formUnion(segmentFlags)
                continue
            }
            if let credit = TrackMatcher.credits(in: segment) {
                extras.formUnion(credit.names)
                kept.append(credit.head)
                continue
            }
            if TrackMatcher.isNoise(segment) { continue }
            kept.append(segment)
        }
        var titleText = (split.main + kept).joined(separator: " ")
        if let credit = TrackMatcher.credits(in: titleText) {
            extras.formUnion(credit.names)
            titleText = credit.head
        }
        title = TrackMatcher.stripTrailingNoise(TrackMatcher.cleanTitle(titleText))
        titleTokens = Set(title.split(separator: " ").map(String.init))

        let artistText = TrackMatcher.fold(track.artist)
            .replacingOccurrences(of: " - topic", with: "")
            .replacingOccurrences(of: " -topic", with: "")
        let names = TrackMatcher.artistNames(artistText)
        artists = Set(names)
        primaryArtist = names.first ?? ""
        extras.formUnion(names.dropFirst())

        album = TrackMatcher.cleanTitle(TrackMatcher.fold(track.album))
        duration = track.durationSeconds
        isrc = track.isrc?.normalizedISRC
        self.extras = extras
        self.flags = flags
    }

}

extension String {
    /// ISRCs are compared without separators or case.
    var normalizedISRC: String {
        uppercased().filter { $0.isLetter || $0.isNumber }
    }
}
