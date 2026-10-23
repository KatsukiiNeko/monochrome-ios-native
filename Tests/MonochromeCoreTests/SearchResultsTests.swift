// SearchResultsTests.swift: chips only for returned types and section filtering.
import Testing
@testable import MonochromeCore

@Suite("SearchResults")
struct SearchResultsTests {
    private let track = Track(id: "track", title: "Song")
    private let release = RemoteRelease(id: "release", title: "Album")
    private let artist = RemoteArtist(id: "artist", name: "Artist")

    @Test func allIsOfferedWithAnyResult() {
        #expect(SearchResults.availableKinds(hasTracks: true, hasReleases: false, hasArtists: false) == [.all, .songs])
        #expect(SearchResults.availableKinds(hasTracks: false, hasReleases: true, hasArtists: false) == [.all, .albums])
        #expect(SearchResults.availableKinds(hasTracks: false, hasReleases: false, hasArtists: true) == [.all, .artists])
    }

    @Test func noResultsOffersNoChips() {
        #expect(SearchResults.availableKinds(hasTracks: false, hasReleases: false, hasArtists: false).isEmpty)
    }

    @Test func allKeepsEverySection() {
        let sections = SearchResults.apply(
            .all,
            tracks: [track],
            releases: [release],
            artists: [artist]
        )
        #expect(sections.tracks == [track])
        #expect(sections.releases == [release])
        #expect(sections.artists == [artist])
    }

    @Test func eachFilterKeepsOnlyItsSection() {
        let songs = SearchResults.apply(.songs, tracks: [track], releases: [release], artists: [artist])
        #expect(songs.tracks == [track])
        #expect(songs.releases.isEmpty)
        #expect(songs.artists.isEmpty)

        let albums = SearchResults.apply(.albums, tracks: [track], releases: [release], artists: [artist])
        #expect(albums.releases == [release])
        #expect(albums.tracks.isEmpty)

        let artists = SearchResults.apply(.artists, tracks: [track], releases: [release], artists: [artist])
        #expect(artists.artists == [artist])
        #expect(artists.releases.isEmpty)
    }
}
