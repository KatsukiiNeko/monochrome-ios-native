// TrackTests.swift: host tests for the track model's Codable behavior.
import Foundation
import Testing
@testable import MonochromeCore

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
