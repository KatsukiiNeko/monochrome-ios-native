// TrackMatcherTests.swift: the synthetic must-match and must-reject corpus.
import Foundation
import Testing
@testable import MonochromeCore

private let companion = MusicSourceID.youTubeMusic.rawValue
private let hifi = MusicSourceID.monochrome.rawValue

private func track(
    _ title: String,
    by artist: String,
    seconds: Double? = 200,
    isrc: String? = nil,
    album: String = "",
    provider: String = companion
) -> Track {
    Track(
        id: "\(provider):\(title)|\(artist)",
        title: title,
        artist: artist,
        album: album,
        durationSeconds: seconds,
        provider: provider,
        streamID: "id-\(title)",
        isrc: isrc
    )
}

private struct Pair {
    let name: String
    let candidate: Track
    let reference: Track

    init(_ name: String, _ candidate: Track, _ reference: Track) {
        self.name = name
        self.candidate = candidate
        self.reference = reference
    }
}

/// The reference side is always a plain catalog track; the candidate is the
/// companion-style variant built from it.
private let base = track(
    "Neon Harbour",
    by: "Aster Vale",
    seconds: 200,
    album: "Harbour Lights",
    provider: hifi
)

private let mustMatch: [Pair] = [
    Pair("identical", track("Neon Harbour", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("official video", track("Neon Harbour (Official Video)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("official audio", track("Neon Harbour [Official Audio]", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("audio after dash", track("Neon Harbour - Official Audio", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("lyrics", track("Neon Harbour (Lyrics)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("lyric video", track("Neon Harbour (Lyric Video)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("visualizer", track("Neon Harbour (Visualizer)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("hd suffix", track("Neon Harbour HD", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("hq suffix", track("Neon Harbour HQ", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("4k suffix", track("Neon Harbour 4K", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("m/v", track("Neon Harbour (M/V)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("topic artist", track("Neon Harbour", by: "Aster Vale - Topic", album: "Harbour Lights"), base),
    Pair(
        "feat moved to artist",
        track("Neon Harbour (feat. Lumen Bay)", by: "Aster Vale", album: "Harbour Lights"),
        track("Neon Harbour", by: "Aster Vale feat. Lumen Bay", album: "Harbour Lights", provider: hifi)
    ),
    Pair(
        "diacritics",
        track("Café Lights", by: "Aster Vale"),
        track("Cafe Lights", by: "Aster Vale", provider: hifi)
    ),
    Pair(
        "and versus ampersand in title",
        track("Gold & Silver", by: "Aster Vale"),
        track("Gold and Silver", by: "Aster Vale", provider: hifi)
    ),
    Pair("case", track("NEON HARBOUR", by: "ASTER VALE", album: "HARBOUR LIGHTS"), base),
    Pair("duration plus two", track("Neon Harbour", by: "Aster Vale", seconds: 202, album: "Harbour Lights"), base),
    Pair("duration plus three", track("Neon Harbour", by: "Aster Vale", seconds: 203, album: "Harbour Lights"), base),
    Pair("duration minus three", track("Neon Harbour", by: "Aster Vale", seconds: 197, album: "Harbour Lights"), base),
    Pair(
        "isrc equal",
        track("Neon Harbor", by: "Aster Vale", isrc: "US-AAA-24-00001"),
        track("Neon Harbour", by: "Aster Vale", isrc: "USAAA2400001", provider: hifi)
    ),
    Pair("punctuation", track("Neon Harbour!", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("combined noise", track("Neon Harbour (Official Video) [HD]", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair(
        "artist ampersand",
        track("Neon Harbour", by: "Aster Vale & Lumen Bay"),
        track("Neon Harbour", by: "Aster Vale and Lumen Bay", provider: hifi)
    ),
    Pair("artist trailing spaces", track("Neon Harbour", by: "Aster Vale  ", album: "Harbour Lights"), base),
    Pair(
        "ft variant",
        track("Neon Harbour ft. Lumen Bay", by: "Aster Vale", album: "Harbour Lights"),
        track("Neon Harbour", by: "Aster Vale feat. Lumen Bay", provider: hifi)
    ),
    Pair(
        "featuring variant",
        track("Neon Harbour featuring Lumen Bay", by: "Aster Vale", album: "Harbour Lights"),
        track("Neon Harbour", by: "Aster Vale feat. Lumen Bay", provider: hifi)
    ),
    Pair("curly quotes", track("“Neon Harbour”", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair(
        "album equal",
        track("Neon Harbour", by: "Aster Vale", album: "Harbour Lights"),
        track("Neon Harbour", by: "Aster Vale", album: "Harbour Lights", provider: hifi)
    ),
    Pair(
        "album different",
        track("Neon Harbour", by: "Aster Vale", album: "Single"),
        track("Neon Harbour", by: "Aster Vale", album: "Harbour Lights", provider: hifi)
    ),
    Pair(
        "apostrophe",
        track("Don't Wait", by: "Aster Vale"),
        track("Dont Wait", by: "Aster Vale", provider: hifi)
    ),
    Pair(
        "hyphen",
        track("Half-Light", by: "Aster Vale"),
        track("Half Light", by: "Aster Vale", provider: hifi)
    ),
    Pair("candidate duration unknown", track("Neon Harbour", by: "Aster Vale", seconds: nil), base),
    Pair(
        "both durations unknown",
        track("Neon Harbour", by: "Aster Vale", seconds: nil),
        track("Neon Harbour", by: "Aster Vale", seconds: nil, provider: hifi)
    ),
    Pair(
        "remaster on both sides",
        track("Neon Harbour (2024 Remaster)", by: "Aster Vale"),
        track("Neon Harbour (2024 Remaster)", by: "Aster Vale", provider: hifi)
    ),
    Pair("remaster on one side", track("Neon Harbour (2024 Remaster)", by: "Aster Vale"), base),
    Pair("explicit on one side", track("Neon Harbour (Explicit)", by: "Aster Vale"), base),
    Pair(
        "extra credit on one side",
        track("Neon Harbour", by: "Aster Vale, Lumen Bay"),
        track("Neon Harbour", by: "Aster Vale", provider: hifi)
    ),
    Pair(
        "noise plus feat",
        track("Neon Harbour (Official Video) [feat. Lumen Bay]", by: "Aster Vale"),
        track("Neon Harbour", by: "Aster Vale feat. Lumen Bay", provider: hifi)
    ),
    Pair(
        "topic and feat",
        track("Neon Harbour", by: "Aster Vale - Topic feat. Lumen Bay"),
        track("Neon Harbour", by: "Aster Vale feat. Lumen Bay", provider: hifi)
    ),
    Pair(
        "ampersand and diacritics",
        track("Café Lights", by: "Aster Vale & Lumen Bay"),
        track("Cafe Lights", by: "Aster Vale and Lumen Bay", provider: hifi)
    ),
    Pair("duration plus one", track("Neon Harbour", by: "Aster Vale", seconds: 201, album: "Harbour Lights"), base),
    Pair("duration minus one", track("Neon Harbour", by: "Aster Vale", seconds: 199, album: "Harbour Lights"), base),
    Pair("official music video", track("Neon Harbour (Official Music Video)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("audio in brackets", track("Neon Harbour (Audio)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("visualizer after dash", track("Neon Harbour - Visualizer", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair(
        "album equal with duration jitter",
        track("Neon Harbour", by: "Aster Vale", seconds: 201.5, album: "Harbour Lights"),
        track("Neon Harbour", by: "Aster Vale", seconds: 200, album: "Harbour Lights", provider: hifi)
    ),
]

private let mustReject: [Pair] = [
    Pair("live", track("Neon Harbour (Live)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("remix", track("Neon Harbour (Remix)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("acoustic", track("Neon Harbour (Acoustic)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("instrumental", track("Neon Harbour (Instrumental)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("sped up", track("Neon Harbour (Sped Up)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("slowed", track("Neon Harbour (Slowed)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("reverb", track("Neon Harbour (Reverb)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("nightcore", track("Neon Harbour (Nightcore)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("cover", track("Neon Harbour (Cover)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("karaoke", track("Neon Harbour (Karaoke)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("8d", track("Neon Harbour (8D Audio)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("live at venue", track("Neon Harbour (Live at Wembley)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("club remix", track("Neon Harbour (Club Remix)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("instrumental version", track("Neon Harbour (Instrumental Version)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("sped up version", track("Neon Harbour (Sped Up Version)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("slowed plus reverb", track("Neon Harbour (Slowed + Reverb)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair("acoustic version", track("Neon Harbour (Acoustic Version)", by: "Aster Vale", album: "Harbour Lights"), base),
    Pair(
        "different artist",
        track("Neon Harbour", by: "Coral Static", album: "Harbour Lights"),
        base
    ),
    Pair(
        "different artist two",
        track("Neon Harbour", by: "The Midnight Ferry", album: "Harbour Lights"),
        base
    ),
    Pair(
        "same artist longer title",
        track("Love Me Now", by: "Aster Vale"),
        track("Love Me", by: "Aster Vale", provider: hifi)
    ),
    Pair(
        "same artist different pronoun",
        track("Hold Me", by: "Aster Vale"),
        track("Hold On", by: "Aster Vale", provider: hifi)
    ),
    Pair(
        "same artist short title",
        track("Fireworks", by: "Aster Vale"),
        track("Fire", by: "Aster Vale", provider: hifi)
    ),
    Pair(
        "intro versus outro",
        track("Outro", by: "Aster Vale"),
        track("Intro", by: "Aster Vale", provider: hifi)
    ),
    Pair(
        "part one versus part two",
        track("Neon Harbour Part 1", by: "Aster Vale", album: "Harbour Lights"),
        track("Neon Harbour Part 2", by: "Aster Vale", album: "Harbour Lights", provider: hifi)
    ),
    Pair(
        "duration plus eleven",
        track("Neon Harbour", by: "Aster Vale", seconds: 211, album: "Harbour Lights"),
        base
    ),
    Pair(
        "duration minus twelve",
        track("Neon Harbour", by: "Aster Vale", seconds: 188, album: "Harbour Lights"),
        base
    ),
    Pair(
        "duration far off",
        track("Neon Harbour", by: "Aster Vale", seconds: 231, album: "Harbour Lights"),
        base
    ),
    Pair(
        "isrc different",
        track("Neon Harbour", by: "Aster Vale", isrc: "US-AAA-24-00002", album: "Harbour Lights"),
        track("Neon Harbour", by: "Aster Vale", isrc: "US-AAA-24-00001", album: "Harbour Lights", provider: hifi)
    ),
    Pair(
        "isrc different near identical",
        track("Neon Harbour", by: "Aster Vale", seconds: 200, isrc: "GBAYE2400002", album: "Harbour Lights"),
        track("Neon Harbour", by: "Aster Vale", seconds: 200, isrc: "GBAYE2400001", album: "Harbour Lights", provider: hifi)
    ),
    Pair(
        "primary artist flips",
        track("Neon Harbour", by: "Aster Vale feat. Lumen Bay"),
        track("Neon Harbour", by: "Lumen Bay feat. Aster Vale", provider: hifi)
    ),
    Pair(
        "midnight drive versus train",
        track("Midnight Train", by: "Aster Vale"),
        track("Midnight Drive", by: "Aster Vale", provider: hifi)
    ),
    Pair(
        "golden hour part two",
        track("Golden Hour Pt. 2", by: "Aster Vale"),
        track("Golden Hour", by: "Aster Vale", provider: hifi)
    ),
    Pair(
        "duration far off two",
        track("Neon Harbour", by: "Aster Vale", seconds: 215, album: "Harbour Lights"),
        base
    ),
    Pair(
        "duration far off three",
        track("Neon Harbour", by: "Aster Vale", seconds: 179, album: "Harbour Lights"),
        base
    ),
    Pair(
        "different artist with feat",
        track("Neon Harbour", by: "Coral Static feat. Lumen Bay"),
        base
    ),
    Pair(
        "different song same album",
        track("Harbour Lights", by: "Aster Vale", album: "Harbour Lights"),
        base
    ),
    Pair(
        "same artist plural title",
        track("Neon Harbours", by: "Aster Vale"),
        base
    ),
    Pair(
        "same artist word added",
        track("Neon Harbour Tonight", by: "Aster Vale"),
        base
    ),
    Pair(
        "same artist one word swapped",
        track("Neon Valley", by: "Aster Vale"),
        base
    ),
    Pair(
        "different title same artist",
        track("Static Bloom", by: "Aster Vale"),
        base
    ),
    Pair(
        "live in artist field",
        track("Neon Harbour", by: "Aster Vale (Live)"),
        base
    ),
    Pair(
        "remix in artist field",
        track("Neon Harbour", by: "Aster Vale Remix"),
        base
    ),
    Pair(
        "featured artist only on one side with different primary",
        track("Neon Harbour", by: "Lumen Bay"),
        track("Neon Harbour", by: "Aster Vale feat. Lumen Bay", provider: hifi)
    ),
]

@Suite("Track matcher corpus")
struct TrackMatcherCorpusTests {
    private let matcher = TrackMatcher()

    @Test("no must-reject pair is accepted")
    func zeroFalseAccepts() {
        let falseAccepts = mustReject
            .filter { matcher.isMatch($0.candidate, $0.reference) }
            .map(\.name)
        #expect(falseAccepts.isEmpty, "Accepted pairs that must be rejected: \(falseAccepts)")
        #expect(mustReject.count >= 40)
    }

    @Test("at least ninety percent of must-match pairs are accepted")
    func acceptRate() {
        let missed = mustMatch
            .filter { !matcher.isMatch($0.candidate, $0.reference) }
            .map(\.name)
        let accepted = mustMatch.count - missed.count
        let rate = Double(accepted) / Double(mustMatch.count)
        #expect(rate >= 0.9, "Accepted \(accepted) of \(mustMatch.count); missed: \(missed)")
        #expect(mustMatch.count >= 40)
    }
}

@Suite("Track matcher rules")
struct TrackMatcherRuleTests {
    private let matcher = TrackMatcher()

    @Test("an equal ISRC wins without looking at the text")
    func isrcWins() throws {
        let match = try #require(matcher.match(
            track("Completely Different", by: "Someone Else", isrc: "US-AAA-24-00001"),
            against: track("Neon Harbour", by: "Aster Vale", isrc: "USAAA2400001", provider: hifi)
        ))
        #expect(match.method == .isrc)
        #expect(match.confidence == 1)
    }

    @Test("a different ISRC rejects a textually identical pair")
    func isrcRejects() {
        #expect(matcher.match(
            track("Neon Harbour", by: "Aster Vale", isrc: "US-AAA-24-00002"),
            against: track("Neon Harbour", by: "Aster Vale", isrc: "US-AAA-24-00001", provider: hifi)
        ) == nil)
    }

    @Test("a duration gap above ten seconds rejects")
    func durationRejects() {
        #expect(matcher.match(
            track("Neon Harbour", by: "Aster Vale", seconds: 211),
            against: base
        ) == nil)
    }

    @Test("a soft version flag lowers the score but still matches")
    func softFlagPenalty() throws {
        let clean = try #require(matcher.match(
            track("Neon Harbour", by: "Aster Vale", album: "Harbour Lights"),
            against: base
        ))
        let remaster = try #require(matcher.match(
            track("Neon Harbour (2024 Remaster)", by: "Aster Vale", album: "Harbour Lights"),
            against: base
        ))
        #expect(remaster.confidence < clean.confidence)
        #expect(remaster.confidence >= TrackMatcher.defaultMinimumConfidence)
    }

    @Test("radio edit is one flag, not edit as well")
    func radioEditFlag() {
        let flags = TrackMatcher.versionFlags(in: "Radio Edit")
        #expect(flags == [.radioEdit])
        #expect(TrackMatcher.versionFlags(in: "8D Audio") == [.eightD])
        #expect(TrackMatcher.versionFlags(in: "Sped Up") == [.spedUp])
        #expect(TrackMatcher.versionFlags(in: "Neon Harbour") == [])
    }

    @Test("normalization strips topic, noise, feat and diacritics")
    func normalization() {
        #expect(TrackMatcher.cleanTitle("Café  Lights!") == "cafe lights")
        #expect(TrackMatcher.fold("Gold & Silver") == "gold  and  silver")
        let normalized = NormalizedTrack(track("Neon Harbour (Official Video) [feat. Lumen Bay]", by: "Aster Vale - Topic"))
        #expect(normalized.title == "neon harbour")
        #expect(normalized.primaryArtist == "aster vale")
        #expect(normalized.extras == ["lumen bay"])
        #expect(TrackMatcher.stripTrailingNoise("neon harbour hd") == "neon harbour")
        #expect(TrackMatcher.stripTrailingNoise("video games") == "video games")
    }

    @Test("best match picks the highest score above the threshold")
    func bestMatch() throws {
        let candidates = [
            track("Neon Harbour (Live)", by: "Aster Vale"),
            track("Neon Harbour", by: "Aster Vale", album: "Harbour Lights"),
            track("Neon Harbour HD", by: "Aster Vale", seconds: 240),
        ]
        let best = try #require(matcher.bestMatch(for: base, among: candidates))
        #expect(best.track.title == "Neon Harbour")
    }

    @Test("a legacy track record without an ISRC still decodes")
    func legacyTrackDecoding() throws {
        let json = """
        {"id":"stream:7","title":"Neon Harbour","artist":"Aster Vale","provider":"monochrome","streamID":"7"}
        """
        let decoded = try JSONDecoder().decode(Track.self, from: Data(json.utf8))
        #expect(decoded.isrc == nil)
        #expect(decoded.title == "Neon Harbour")
    }
}
