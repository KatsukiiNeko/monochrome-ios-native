// PlaylistImportTests.swift: file parsers, match scoring and the importer loop.
import Foundation
import Testing
@testable import MonochromeCore

private func track(
    _ id: String,
    title: String,
    artist: String,
    album: String = "",
    duration: Double? = nil
) -> Track {
    Track(
        id: Track.remoteIDPrefix + id,
        title: title,
        artist: artist,
        album: album,
        durationSeconds: duration,
        provider: "monochrome",
        streamID: id
    )
}

@Suite("Playlist file parser")
struct PlaylistFileParserTests {
    @Test("CSV with header, sniffed delimiter and quoted fields")
    func csvWithHeader() {
        // The sample uses semicolons throughout so the sniffed delimiter is
        // unambiguous; the quoted field still contains a semicolon.
        let csv = """
        "Title";"Artist";Album;Duration
        "One; Two";Daft Punk;Discovery;3:45
        "Around the World, ";Daft Punk;Discovery;225
        ;;;;
        """
        let result = PlaylistFileParser.parse(Data(csv.utf8))
        #expect(result.format == .csv)
        #expect(result.entries.count == 2)
        #expect(result.skipped == 1)
        let first = result.entries[0]
        #expect(first.title == "One; Two")
        #expect(first.artist == "Daft Punk")
        #expect(first.album == "Discovery")
        #expect(first.durationSeconds == 225)
        #expect(result.entries[1].title == "Around the World,")
        #expect(result.entries[1].durationSeconds == 225)
    }

    @Test("CSV without a header assumes Artist - Title in one column or Title,Artist")
    func csvWithoutHeader() {
        let comma = "Daft Punk,Digital Love\n"
        let result = PlaylistFileParser.parse(Data(comma.utf8))
        #expect(result.entries.count == 1)
        #expect(result.entries[0].title == "Digital Love")
        #expect(result.entries[0].artist == "Daft Punk")

        let combined = "Daft Punk - Digital Love\nSomething Else\n"
        let combinedResult = PlaylistFileParser.parse(Data(combined.utf8))
        #expect(combinedResult.entries.count == 1)
        #expect(combinedResult.entries[0].artist == "Daft Punk")
        #expect(combinedResult.skipped == 1)
    }

    @Test("a UTF-8 BOM is tolerated")
    func bom() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("Title,Artist\nSong,Artist\n".utf8))
        let result = PlaylistFileParser.parse(data)
        #expect(result.entries.count == 1)
        #expect(result.entries[0].title == "Song")
    }

    @Test("M3U uses EXTINF labels and skips paths without one")
    func m3u() {
        let m3u = """
        #EXTM3U
        #EXTINF:201,Daft Punk - Get Lucky
        /music/get-lucky.flac
        #EXTINF:60,Naked path song
        another/path.mp3
        /music/loose-path.mp3
        #EXTINF:99,Daft Punk - One More Time
        /music/one-more-time.flac
        """
        let result = PlaylistFileParser.parse(Data(m3u.utf8))
        #expect(result.format == .m3u)
        // A label may carry only a title; the path lines are not entries.
        #expect(result.entries.count == 3)
        #expect(result.skipped == 1)
        #expect(result.entries[0].title == "Get Lucky")
        #expect(result.entries[0].artist == "Daft Punk")
        #expect(result.entries[0].durationSeconds == 201)
        #expect(result.entries[1].title == "Naked path song")
    }

    @Test("plain text accepts dashes and dashes with spaces")
    func text() {
        let text = """
        # comment
        Daft Punk - Digital Love
        Gorillaz – Feel Good Inc.
        noparseparator
        \t \t

        """
        let result = PlaylistFileParser.parse(Data(text.utf8))
        #expect(result.format == .text)
        #expect(result.entries.count == 2)
        #expect(result.entries[0].title == "Digital Love")
        #expect(result.entries[1].artist == "Gorillaz")
        #expect(result.skipped == 1)
    }

    @Test("the app's own JSON round trips through snapshots")
    func appJSONRoundTrip() throws {
        let tracks = [
            track("1", title: "One", artist: "A", album: "X", duration: 100),
            track("2", title: "Two", artist: "B", album: "Y", duration: 200),
        ]
        let data = try PlaylistFileParser.appExportJSON(name: "Mix", items: tracks)
        let result = PlaylistFileParser.parse(data)
        #expect(result.format == .json)
        #expect(result.playlistName == "Mix")
        #expect(result.entries.count == 2)
        #expect(result.entries[0].snapshot == tracks[0])
    }

    @Test("duration parsing handles clock and seconds")
    func durationParsing() {
        #expect(PlaylistFileParser.parseDuration("3:45") == 225)
        #expect(PlaylistFileParser.parseDuration("225") == 225)
        #expect(PlaylistFileParser.parseDuration("-5") == nil)
        #expect(PlaylistFileParser.parseDuration("") == nil)
        #expect(PlaylistFileParser.parseDuration("abc") == nil)
    }

    @Test("CSV export quotes fields and round trips through the parser")
    func csvExport() {
        let items = [
            track("1", title: "One, Two", artist: "Artist \"A\"", album: "Album", duration: 225),
            track("2", title: "Three", artist: "Artist B", album: "Album", duration: 100),
        ]
        let csv = PlaylistFileParser.appExportCSV(items: items)
        #expect(csv.hasPrefix("Title,Artist,Album,Duration\n"))

        let parsed = PlaylistFileParser.parseCSV(csv)
        #expect(parsed.entries.count == 2)
        #expect(parsed.entries[0].title == "One, Two")
        #expect(parsed.entries[0].artist == "Artist \"A\"")
        #expect(parsed.entries[0].durationSeconds == 225)
        #expect(parsed.entries[1].title == "Three")
    }

    @Test("a progress file without a schema version migrates in place")
    func progressMigration() throws {
        let legacy = """
        {"playlistName":"Old","pending":[{"title":"Song","artist":"Artist"}],"settled":[],"searchFailures":0}
        """
        let progress = try JSONDecoder().decode(PlaylistImportProgress.self, from: Data(legacy.utf8))
        #expect(progress.schemaVersion == PlaylistImportProgress.schemaVersion)
        #expect(progress.playlistName == "Old")
        #expect(progress.pending.count == 1)
    }
}

@Suite("Playlist matcher")
struct PlaylistMatcherTests {
    private let entry = PlaylistImportEntry(
        title: "Digital Love",
        artist: "Daft Punk",
        album: "Discovery",
        durationSeconds: 200
    )

    @Test("an exact candidate clears the auto-accept threshold")
    func exactMatch() {
        let candidate = track("1", title: "Digital Love", artist: "Daft Punk", album: "Discovery", duration: 199)
        let outcome = PlaylistMatcher.match(entry: entry, candidates: [candidate])
        #expect(outcome.accepted != nil)
        #expect(outcome.accepted?.score == 1.0)
        #expect(outcome.reviewCandidates.isEmpty)
    }

    @Test("a different song stays in review with a few candidates")
    func reviewFlow() {
        let candidates = [
            track("1", title: "Something Else", artist: "Other Artist", album: "B", duration: 90),
            track("2", title: "Digital World", artist: "Daft Punk", album: "Discovery", duration: 199),
        ]
        let outcome = PlaylistMatcher.match(entry: entry, candidates: candidates)
        #expect(outcome.accepted == nil)
        #expect(outcome.reviewCandidates.count <= PlaylistMatcher.reviewCandidateCount)
        #expect(outcome.reviewCandidates.first?.candidate.id == Track.remoteIDPrefix + "2")
    }

    @Test("duration drift lowers the score but tolerance forgives small drift")
    func durationPenalty() {
        let near = track("1", title: "Digital Love", artist: "Daft Punk", album: "Discovery", duration: 202)
        let far = track("2", title: "Digital Love", artist: "Daft Punk", album: "Discovery", duration: 400)
        #expect(PlaylistMatcher.score(entry: entry, candidate: near) == 1.0)
        #expect(PlaylistMatcher.score(entry: entry, candidate: far) < 0.85)
    }

    @Test("normalization ignores case, punctuation and diacritics")
    func normalization() {
        #expect(PlaylistMatcher.similarity("Beyoncé - Halo (Live)", "beyonce halo live") == 1.0)
        #expect(PlaylistMatcher.similarity("", "something") == 0.0)
    }
}

/// Counting box for the search-call assertion.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private func searchTracks(_ ids: [String]) -> [Track] {
    ids.map { track($0, title: "Song \($0)", artist: "Artist \($0)", duration: 100) }
}

@MainActor
@Suite("Playlist importer")
struct PlaylistImporterTests {
    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(name + "-\(UUID().uuidString).json")
    }

    @Test("exact candidates are auto-accepted and others land in review")
    func autoAcceptAndReview() async {
        let importer = PlaylistImporter()
        let entries = [
            PlaylistImportEntry(title: "Song a", artist: "Artist a"),
            PlaylistImportEntry(title: "Mystery", artist: "Unknown"),
        ]
        let dropped = importer.start(
            name: "Import",
            entries: entries,
            search: { query in
                query.contains("Artist a") ? searchTracks(["a"]) : []
            },
            store: temporaryURL("import-a")
        )
        #expect(dropped == 0)
        // Wait for the loop to drain both entries plus the spacing.
        for _ in 0..<20 where importer.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        #expect(!importer.isRunning)
        #expect(importer.processed == 2)
        #expect(importer.chosenTracks.count == 1)
        #expect(importer.reviewEntries.count == 1)
    }

    @Test("failed searches are counted and never stop the loop")
    func searchFailure() async {
        let importer = PlaylistImporter()
        _ = importer.start(
            name: "Import",
            entries: [PlaylistImportEntry(title: "X", artist: "Y")],
            search: { _ in throw TracksAPIError.unavailable("offline") },
            store: temporaryURL("import-fail")
        )
        for _ in 0..<20 where importer.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        #expect(importer.searchFailures == 1)
        #expect(importer.chosenTracks.isEmpty)
    }

    @Test("progress survives a cancel and resumes without repeating work")
    func resume() async throws {
        let url = temporaryURL("import-resume")
        let importer = PlaylistImporter()
        let entries = (0..<6).map { PlaylistImportEntry(title: "Song \($0)", artist: "Artist \($0)") }
        _ = importer.start(name: "Six", entries: entries, search: { query in
            // Every search returns its own exact match.
            let title = query.dropFirst("Artist ".count)
            return searchTracks([String(title.prefix(1))])
        }, store: url)

        // Let it settle a couple of entries, then pause.
        for _ in 0..<40 where importer.isRunning && importer.processed < 2 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        importer.pause()

        let second = PlaylistImporter()
        let resumed = second.resume(store: url) { query in
            let title = query.dropFirst("Artist ".count)
            return searchTracks([String(title.prefix(1))])
        }
        #expect(resumed)
        for _ in 0..<60 where second.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        #expect(second.processed == 6)
        #expect(second.chosenTracks.count == 6)
        #expect(second.reviewEntries.isEmpty)
    }

    @Test("the cap truncates and the count reports the drop")
    func cap() async {
        let importer = PlaylistImporter()
        let entries = (0..<PlaylistImporter.maxEntries + 7).map {
            PlaylistImportEntry(title: "Song \($0)", artist: "Artist")
        }
        let dropped = importer.start(
            name: "Big",
            entries: entries,
            search: { _ in [] },
            store: temporaryURL("import-cap")
        )
        #expect(dropped == 7)
        importer.cancel()
    }

    @Test("review choices and rejections shape the final list")
    func reviewDecisions() async throws {
        let importer = PlaylistImporter()
        let entries = [PlaylistImportEntry(title: "Ambiguous", artist: "Someone")]
        // Similar titles but a different artist: too weak to auto-accept.
        let candidates = [
            track("1", title: "Ambiguous Song", artist: "Other", duration: 100),
            track("2", title: "Ambiguous Tune", artist: "Another", duration: 100),
        ]
        _ = importer.start(name: "R", entries: entries, search: { _ in candidates }, store: temporaryURL("import-review"))
        for _ in 0..<20 where importer.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }

        let review = importer.reviewEntries[0]
        #expect(review.reviewCandidates.count == 2)
        importer.reject(review)
        #expect(importer.reviewEntries.isEmpty)
        #expect(importer.chosenTracks.isEmpty)

        // A second run where the user picks a candidate.
        let second = PlaylistImporter()
        _ = second.start(name: "R", entries: entries, search: { _ in candidates }, store: temporaryURL("import-review2"))
        for _ in 0..<20 where second.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let secondReview = second.reviewEntries[0]
        second.choose(secondReview, track: secondReview.reviewCandidates[1])
        #expect(second.chosenTracks.map(\.id) == [Track.remoteIDPrefix + "2"])
        #expect(second.chosenTracks[0].id == secondReview.reviewCandidates[1].id)
    }

    @Test("app snapshots bypass the network")
    func snapshotsSkipSearch() async {
        let importer = PlaylistImporter()
        let searchCalls = Counter()
        let entry = PlaylistImportEntry(
            title: "One",
            artist: "A",
            snapshot: track("snap", title: "One", artist: "A")
        )
        _ = importer.start(
            name: "Snap",
            entries: [entry],
            search: { _ in
                searchCalls.increment()
                return []
            },
            store: temporaryURL("import-snap")
        )
        for _ in 0..<20 where importer.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        #expect(searchCalls.count == 0)
        #expect(importer.chosenTracks.first?.id == Track.remoteIDPrefix + "snap")
    }
}
