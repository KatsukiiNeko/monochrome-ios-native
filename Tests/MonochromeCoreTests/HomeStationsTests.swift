// HomeStationsTests.swift: which artist names the home station row may offer.
import Testing
@testable import MonochromeCore

@Suite("Home stations")
struct HomeStationsTests {
    private func track(_ artist: String, _ title: String = "song") -> Track {
        Track(title: title, artist: artist)
    }

    @Test("favorites come first, then recents")
    func order() {
        let names = HomeStations.artists(
            favorites: [track("A"), track("B")],
            recents: [track("C")]
        )
        #expect(names == ["A", "B", "C"])
    }

    @Test("a repeated artist appears once, whatever the case")
    func dedupe() {
        let names = HomeStations.artists(
            favorites: [track("A"), track("a")],
            recents: [track("A"), track("B")]
        )
        #expect(names == ["A", "B"])
    }

    @Test("an empty artist is never a seed")
    func emptyArtist() {
        let names = HomeStations.artists(
            favorites: [track(""), track("  ")],
            recents: [track("B")]
        )
        #expect(names == ["B"])
    }

    @Test("the limit applies and a zero limit yields nothing")
    func limit() {
        let favorites = [track("A"), track("B"), track("C"), track("D")]
        #expect(HomeStations.artists(favorites: favorites, recents: []).count == 4)
        #expect(HomeStations.artists(favorites: favorites, recents: [], limit: 2) == ["A", "B"])
        #expect(HomeStations.artists(favorites: favorites, recents: [], limit: 0).isEmpty)
    }
}
