// LibraryQueryTests.swift: filter, de-duplication and sort order for library rows.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("LibraryQuery")
struct LibraryQueryTests {
    private func track(
        _ id: String,
        title: String,
        artist: String = "",
        local: Bool = true,
        added: TimeInterval = 0
    ) -> Track {
        Track(
            id: id,
            title: title,
            artist: artist,
            importedAt: Date(timeIntervalSince1970: added),
            provider: local ? Track.localProvider : "catalog"
        )
    }

    @Test func allMergesLocalAndFavoriteTracksWithoutDuplicates() {
        let local = track("a", title: "A")
        let favorite = track("b", title: "B", local: false)
        let rows = LibraryQuery.rows(
            tracks: [local],
            favorites: [local, favorite],
            filter: .all,
            sort: .title
        )
        #expect(rows.map(\.id) == ["a", "b"])
    }

    @Test func favoritesAndLocalUseTheirOwnLists() {
        let local = track("a", title: "A")
        let favorite = track("b", title: "B", local: false)
        #expect(
            LibraryQuery.rows(tracks: [local], favorites: [favorite], filter: .favorites, sort: .title)
                .map(\.id) == ["b"]
        )
        #expect(
            LibraryQuery.rows(tracks: [local], favorites: [favorite], filter: .local, sort: .title)
                .map(\.id) == ["a"]
        )
    }

    @Test func sortsByTitleArtistAndRecentlyAdded() {
        let a = track("a", title: "Alpha", artist: "Zed", added: 10)
        let b = track("b", title: "Beta", artist: "Amy", added: 20)
        let c = track("c", title: "Alpha", artist: "Amy", added: 30)

        #expect(
            LibraryQuery.rows(tracks: [b, c, a], favorites: [], filter: .local, sort: .title)
                .map(\.id) == ["a", "c", "b"]
        )
        #expect(
            LibraryQuery.rows(tracks: [b, c, a], favorites: [], filter: .local, sort: .artist)
                .map(\.id) == ["c", "b", "a"]
        )
        #expect(
            LibraryQuery.rows(tracks: [a, b, c], favorites: [], filter: .local, sort: .recent)
                .map(\.id) == ["c", "b", "a"]
        )
    }
}
