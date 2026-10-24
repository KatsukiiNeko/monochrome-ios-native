// LyricsMatcherTests.swift: rejection and selection rules for provider candidates.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("LyricsMatcher")
struct LyricsMatcherTests {
    private func query(
        title: String = "Synthetic Song",
        artist: String = "Synthetic Artist",
        duration: TimeInterval? = 200
    ) -> LyricsQuery {
        LyricsQuery(
            trackID: "track-1",
            title: title,
            artist: artist,
            album: "Synthetic Album",
            duration: duration
        )
    }

    private func candidate(
        title: String = "Synthetic Song",
        artist: String = "Synthetic Artist",
        duration: TimeInterval? = 200,
        synced: Bool = true,
        plain: Bool = true,
        instrumental: Bool = false
    ) -> LyricsCandidate {
        LyricsCandidate(
            trackName: title,
            artistName: artist,
            albumName: "Synthetic Album",
            duration: duration,
            hasSyncedLyrics: synced,
            hasPlainLyrics: plain,
            instrumental: instrumental
        )
    }

    @Test func exactMetadataMatches() {
        #expect(LyricsMatcher.bestMatch(for: query(), in: [candidate()]) != nil)
    }

    @Test func casePunctuationAndAmpersandsAreIgnored() {
        let query = query(title: "Don't Stop Me Now", artist: "Simon & Garfunkel")
        let candidate = candidate(title: "Dont Stop Me Now", artist: "Simon and Garfunkel")
        #expect(LyricsMatcher.bestMatch(for: query, in: [candidate]) != nil)
    }

    @Test func versionSuffixesAndFeaturedArtistsDoNotBlockAMatch() {
        let versions = [
            "Synthetic Song (feat. Another Artist)",
            "Synthetic Song [Remastered 2011]",
            "Synthetic Song - Remastered",
            "Synthetic Song - Live",
            "Synthetic Song - Radio Edit",
        ]
        for version in versions {
            #expect(
                LyricsMatcher.bestMatch(for: query(), in: [candidate(title: version)]) != nil,
                "did not match \(version)"
            )
        }
    }

    @Test func unicodeNormalizationFormsCompareEqual() {
        let composed = "Anh Là Thằng Tồi"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        #expect(composed.unicodeScalars.count != decomposed.unicodeScalars.count)
        #expect(LyricsMatcher.normalized(composed) == LyricsMatcher.normalized(decomposed))

        let query = query(title: composed, artist: "Nghệ Sĩ Thử Nghiệm")
        let candidate = candidate(title: decomposed, artist: "Nghe Si Thu Nghiem")
        #expect(LyricsMatcher.bestMatch(for: query, in: [candidate]) != nil)
    }

    @Test func vietnameseDWithStrokeAndDiacriticsFold() {
        let query = query(title: "Đừng Làm Anh Khó", artist: "Ca Sĩ Việt Nam")
        #expect(LyricsMatcher.normalized(query.title) == "dung lam anh kho")
        #expect(
            LyricsMatcher.bestMatch(
                for: query,
                in: [candidate(title: "Dung Lam Anh Kho", artist: "Ca Si Viet Nam")]
            ) != nil
        )
    }

    @Test func aWrongDurationIsRejectedEvenWhenTheTitleMatches() {
        #expect(LyricsMatcher.bestMatch(for: query(duration: 200), in: [candidate(duration: 204)]) == nil)
        #expect(LyricsMatcher.bestMatch(for: query(duration: 200), in: [candidate(duration: 203)]) != nil)
        #expect(LyricsMatcher.bestMatch(for: query(duration: 200), in: [candidate(duration: nil)]) != nil)
    }

    @Test func aWrongArtistIsRejected() {
        let wrong = candidate(artist: "Completely Different Artist")
        #expect(LyricsMatcher.bestMatch(for: query(), in: [wrong]) == nil)
    }

    @Test func aWrongTitleIsRejected() {
        let wrong = candidate(title: "Another Unrelated Song")
        #expect(LyricsMatcher.bestMatch(for: query(), in: [wrong]) == nil)
    }

    @Test func aQueryWithoutTitleOrArtistIsNeverMatched() {
        let emptyTitle = LyricsQuery(trackID: "1", title: " ", artist: "Artist", duration: 200)
        let emptyArtist = LyricsQuery(trackID: "2", title: "Title", artist: "", duration: 200)
        #expect(emptyTitle.isQueryable == false)
        #expect(emptyArtist.isQueryable == false)
        #expect(LyricsMatcher.bestMatch(for: emptyTitle, in: [candidate()]) == nil)
        #expect(LyricsMatcher.bestMatch(for: emptyArtist, in: [candidate()]) == nil)
    }

    @Test func syncedCandidatesWinTiesOverPlainOnes() {
        let plain = candidate(synced: false, plain: true)
        let synced = candidate(synced: true, plain: true)
        let best = LyricsMatcher.bestMatch(for: query(), in: [plain, synced])
        #expect(best?.hasSyncedLyrics == true)
    }

    @Test func theClosestDurationWinsWhenEverythingElseTies() {
        let near = candidate(duration: 200.5)
        let far = candidate(duration: 202.8)
        #expect(LyricsMatcher.bestMatch(for: query(), in: [far, near])?.duration == 200.5)
    }

    @Test func anInstrumentalAlternateCanBeSelectedWhenItsMetadataMatches() {
        let instrumental = candidate(synced: false, plain: false, instrumental: true)
        #expect(LyricsMatcher.bestMatch(for: query(), in: [instrumental])?.instrumental == true)
    }

    @Test func aSingleWordTitleDoesNotMatchByContainment() {
        let query = query(title: "Home", artist: "Synthetic Artist")
        let wrong = candidate(title: "Coming Home", artist: "Synthetic Artist")
        #expect(LyricsMatcher.bestMatch(for: query, in: [wrong]) == nil)

        let exact = candidate(title: "Home", artist: "Synthetic Artist")
        #expect(LyricsMatcher.bestMatch(for: query, in: [exact]) != nil)
    }

    @Test func aSingleWordArtistDoesNotMatchByContainment() {
        let query = query(title: "Synthetic Song", artist: "Adele")
        let wrong = candidate(title: "Synthetic Song", artist: "Adele Blue Adkins")
        #expect(LyricsMatcher.bestMatch(for: query, in: [wrong]) == nil)
    }

    @Test func aTrackBuildsAQueryOnlyWhenTitleAndArtistExist() {
        let complete = Track(
            id: "stream:42",
            title: "  Synthetic Song  ",
            artist: " Synthetic Artist ",
            album: "  ",
            durationSeconds: 200
        )
        let query = complete.lyricsQuery
        #expect(query?.trackID == "stream:42")
        #expect(query?.title == "Synthetic Song")
        #expect(query?.artist == "Synthetic Artist")
        #expect(query?.album == nil)
        #expect(query?.duration == 200)

        #expect(Track(title: "Title", artist: "").lyricsQuery == nil)
        #expect(Track(title: "", artist: "Artist").lyricsQuery == nil)
    }
}
