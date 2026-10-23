// MusicSourceTests.swift: source identity, capabilities and tolerant decoding.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("MusicSource")
struct MusicSourceTests {
    @Test func monochromeCanDownloadAndYouTubeMusicCannot() {
        #expect(MusicSourceID.monochrome.capabilities.contains(.stream))
        #expect(MusicSourceID.monochrome.supportsDownloads)
        #expect(MusicSourceID.youTubeMusic.capabilities.contains(.stream))
        #expect(!MusicSourceID.youTubeMusic.supportsDownloads)
    }

    @Test func unknownProviderFallsBackToTheDefaultSource() {
        let track = Track(id: "stream:1", title: "A", provider: "unknown")
        #expect(track.source == .monochrome)
    }

    @Test func localFilesUseTheDefaultSourceIdentity() {
        let track = Track(id: "local", title: "A", fileName: "a.m4a", provider: Track.localProvider)
        #expect(track.source == .monochrome)
        #expect(!track.isStreaming)
    }

    @Test func companionSourceRoundTripsThroughCodable() throws {
        let data = try JSONEncoder().encode(MusicSourceID.youTubeMusic)
        let decoded = try JSONDecoder().decode(MusicSourceID.self, from: data)
        #expect(decoded == .youTubeMusic)
    }
}
