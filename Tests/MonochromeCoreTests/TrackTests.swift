// TrackTests.swift: host tests for the track model's Codable behavior.
import Foundation
import Testing
@testable import MonochromeCore

@Test func trackDecodesQualityTolerantly() throws {
    let lossless = try JSONDecoder().decode(
        Track.self,
        from: Data(#"{"id":"t1","title":"Song","audioQuality":"LOSSLESS"}"#.utf8)
    )
    let unknown = try JSONDecoder().decode(
        Track.self,
        from: Data(#"{"id":"t2","title":"Song","audioQuality":"SOMETHING_NEW"}"#.utf8)
    )
    let missing = try JSONDecoder().decode(Track.self, from: Data(#"{"id":"t3","title":"Song"}"#.utf8))

    #expect(lossless.audioQuality == .lossless)
    #expect(unknown.audioQuality == nil)
    #expect(missing.audioQuality == nil)
}

@Test func trackRoundTripsThroughJSON() throws {
    let track = Track(
        id: "t1",
        title: "One More Time",
        artist: "Daft Punk",
        album: "Discovery",
        durationSeconds: 320,
        fileName: "t1.flac",
        importedAt: Date(timeIntervalSince1970: 0)
    )

    let data = try JSONEncoder().encode(track)
    let decoded = try JSONDecoder().decode(Track.self, from: data)

    #expect(decoded == track)
}
