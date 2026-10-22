// AudioBadgeTests.swift: host tests for the quality and parsed-format badge wording.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("AudioBadge")
struct AudioBadgeTests {
    @Test func declaredTiersMapToTheWebAppWording() {
        #expect(AudioBadge.text(quality: .lossless) == "FLAC")
        #expect(AudioBadge.text(quality: .hiResLossless) == "HD FLAC")
        #expect(AudioBadge.text(quality: .high) == "AAC")
        #expect(AudioBadge.text(quality: .low) == "AAC")
    }

    @Test func parsedFormatWinsOverTheDeclaredTier() {
        let format = AudioFormat(codec: "flac", bitDepth: 16, sampleRateHz: 44_100)

        #expect(AudioBadge.text(format: format, quality: .lossless) == "FLAC 16/44.1")
    }

    @Test func highResolutionFormatsUseTheHdPrefix() {
        #expect(AudioBadge.text(format: AudioFormat(codec: "flac", bitDepth: 24, sampleRateHz: 96_000)) == "HD 24/96")
        #expect(AudioBadge.text(format: AudioFormat(codec: "flac", bitDepth: 24, sampleRateHz: 44_100)) == "HD 24/44.1")
    }

    @Test func lossyCodecsUseTheirOwnName() {
        #expect(AudioBadge.text(format: AudioFormat(codec: "aac ")) == "AAC")
        #expect(AudioBadge.text(format: AudioFormat(codec: "mp4a")) == "AAC")
        #expect(AudioBadge.text(format: AudioFormat(codec: ".mp3")) == "MP3")
        #expect(AudioBadge.text(format: AudioFormat(codec: "opus", bitDepth: 16, sampleRateHz: 48_000)) == "Opus")
    }

    @Test func missingOrEmptyDataShowsNoBadge() {
        #expect(AudioBadge.text() == nil)
        #expect(AudioBadge.text(format: AudioFormat(codec: "")) == nil)
    }

    @Test func accessibilityReadsTheTierThenTheFormat() {
        let format = AudioFormat(codec: "flac", bitDepth: 16, sampleRateHz: 44_100)

        #expect(AudioBadge.accessibilityLabel(format: format, quality: .lossless) == "Lossless, FLAC 16/44.1")
        #expect(AudioBadge.accessibilityLabel(quality: .high) == "High, AAC")
        #expect(AudioBadge.accessibilityLabel() == nil)
    }
}
