// AudioSpecTests.swift: host tests for specification formatting, merging and labels.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("AudioSpec")
struct AudioSpecTests {
    @Test func sampleRatesUseKilohertzWithUpToOneDecimal() {
        #expect(AudioSpecFormat.sampleRate(44_100) == "44.1 kHz")
        #expect(AudioSpecFormat.sampleRate(48_000) == "48 kHz")
        #expect(AudioSpecFormat.sampleRate(88_200) == "88.2 kHz")
        #expect(AudioSpecFormat.sampleRate(96_000) == "96 kHz")
        #expect(AudioSpecFormat.sampleRate(176_400) == "176.4 kHz")
        #expect(AudioSpecFormat.sampleRate(192_000) == "192 kHz")
        #expect(AudioSpecFormat.sampleRate(nil) == nil)
        #expect(AudioSpecFormat.sampleRate(0) == nil)
    }

    @Test func spokenSampleRateExpandsTheUnit() {
        #expect(AudioSpecFormat.spokenSampleRate(44_100) == "44.1 kilohertz")
        #expect(AudioSpecFormat.spokenSampleRate(48_000) == "48 kilohertz")
        #expect(AudioSpecFormat.spokenSampleRate(nil) == nil)
    }

    @Test func bitDepthAndChannelsHaveReadableForms() {
        #expect(AudioSpecFormat.bitDepth(16) == "16-bit")
        #expect(AudioSpecFormat.bitDepth(24) == "24-bit")
        #expect(AudioSpecFormat.bitDepth(0) == nil)
        #expect(AudioSpecFormat.bitDepth(nil) == nil)

        #expect(AudioSpecFormat.channels(1) == "Mono")
        #expect(AudioSpecFormat.channels(2) == "Stereo")
        #expect(AudioSpecFormat.channels(6) == "6 ch")
        #expect(AudioSpecFormat.channels(0) == nil)
        #expect(AudioSpecFormat.channels(nil) == nil)
    }

    @Test func estimatedBitrateRoundsAndMarksTheEstimate() {
        #expect(AudioSpecFormat.bitrate(1_411, estimated: true) == "~1410 kbps")
        #expect(AudioSpecFormat.bitrate(1_414, estimated: true) == "~1410 kbps")
        #expect(AudioSpecFormat.bitrate(1_416, estimated: true) == "~1420 kbps")
        #expect(AudioSpecFormat.bitrate(320, estimated: true) == "~320 kbps")
        #expect(AudioSpecFormat.bitrate(1_411, estimated: false) == "1411 kbps")
        #expect(AudioSpecFormat.bitrate(0) == nil)
        #expect(AudioSpecFormat.bitrate(nil) == nil)
    }

    @Test func summaryOmitsEveryUnknownPart() {
        let full = AudioSpec(
            codec: "flac",
            sampleRateHz: 44_100,
            bitDepth: 16,
            source: .stream
        )
        #expect(AudioSpecFormat.summary(for: full) == "FLAC · 16-bit / 44.1 kHz")

        let rateOnly = AudioSpec(codec: "flac", sampleRateHz: 48_000, source: .cache)
        #expect(AudioSpecFormat.summary(for: rateOnly) == "FLAC · 48 kHz")

        let codecOnly = AudioSpec(codec: ".mp3", source: .download)
        #expect(AudioSpecFormat.summary(for: codecOnly) == "MP3")

        #expect(AudioSpecFormat.summary(for: AudioSpec(source: .local)) == nil)
    }

    @Test func detailOnlyShowsKnownFormatParts() {
        let spec = AudioSpec(sampleRateHz: 44_100, bitDepth: 16, source: .stream)
        #expect(AudioSpecFormat.detail(for: spec) == "16-bit / 44.1 kHz")
        #expect(AudioSpecFormat.detail(for: AudioSpec(bitDepth: 24, source: .stream)) == "24-bit")
        #expect(AudioSpecFormat.detail(for: AudioSpec(sampleRateHz: 96_000, source: .stream)) == "96 kHz")
        #expect(AudioSpecFormat.detail(for: AudioSpec(source: .stream)) == nil)
    }

    @Test func fourCCNamesCoverTheSupportedFormatsAndRejectUnknownCodes() {
        #expect(AudioCodecName.displayName(for: "flac") == "FLAC")
        #expect(AudioCodecName.displayName(for: "aac ") == "AAC")
        #expect(AudioCodecName.displayName(for: ".mp3") == "MP3")
        #expect(AudioCodecName.displayName(for: "alac") == "ALAC")
        #expect(AudioCodecName.displayName(for: "opus") == "Opus")
        #expect(AudioCodecName.displayName(for: "FLAC") == "FLAC")
        #expect(AudioCodecName.displayName(for: "zzzz") == nil)
        #expect(AudioCodecName.displayName(for: "") == nil)
        #expect(AudioCodecName.displayName(for: nil) == nil)
    }

    @Test func measuredValuesOverrideReportedOnes() {
        var spec = AudioSpec(
            codec: "flac",
            sampleRateHz: 44_100,
            bitDepth: 16,
            source: .stream,
            provenance: [.codec: .measured, .sampleRate: .reported, .bitDepth: .reported]
        )
        let measured = AudioSpec(
            codec: "alac",
            sampleRateHz: 48_000,
            source: .stream,
            provenance: [.codec: .reported, .sampleRate: .measured]
        )
        var mismatches: [String] = []
        spec.merge(measured, log: { mismatches.append($0) })

        #expect(spec.sampleRateHz == 48_000)
        #expect(spec.provenance(for: .sampleRate) == .measured)
        #expect(spec.bitDepth == 16)
        #expect(spec.provenance(for: .bitDepth) == .reported)
        #expect(spec.codec == "flac")
        #expect(spec.provenance(for: .codec) == .measured)
        #expect(mismatches == [
            "audiospec mismatch field=codec",
            "audiospec mismatch field=sampleRate",
        ])
    }

    @Test func equalProvenanceKeepsTheFresherValueAndFillsGaps() {
        var spec = AudioSpec(
            codec: "flac",
            sampleRateHz: 44_100,
            source: .cache,
            provenance: [.codec: .measured, .sampleRate: .measured]
        )
        let fresh = AudioSpec(
            codec: "flac",
            sampleRateHz: 44_100,
            bitDepth: 24,
            channels: 2,
            bitrateKbps: 1_411,
            source: .cache,
            provenance: [
                .codec: .measured, .sampleRate: .measured, .bitDepth: .measured,
                .channels: .measured, .bitrate: .measured,
            ]
        )
        spec.merge(fresh)

        #expect(spec.bitDepth == 24)
        #expect(spec.channels == 2)
        #expect(spec.bitrateKbps == 1_411)
        #expect(spec.provenance(for: .bitDepth) == .measured)
        #expect(spec.provenance(for: .bitrate) == .measured)
        #expect(spec.provenance(for: .channels) == .measured)
    }

    @Test func provenanceIsAbsentForUnknownFields() {
        let spec = AudioSpec.from(
            format: AudioFormat(codec: "flac", bitDepth: 16, sampleRateHz: 44_100),
            quality: .lossless,
            source: .stream
        )
        #expect(spec.provenance(for: .codec) == .measured)
        #expect(spec.provenance(for: .sampleRate) == .measured)
        #expect(spec.provenance(for: .bitrate) == nil)
        #expect(spec.qualityRequested == .lossless)
        #expect(spec.qualityActual == nil)
    }

    @Test func qualityFallbackOnlyAppearsWhenTiersDiffer() {
        #expect(AudioSpecFormat.qualityFallback(requested: .hiResLossless, actual: .high) == "High-resolution lossless → High")
        #expect(AudioSpecFormat.qualityFallback(requested: .lossless, actual: .lossless) == nil)
        #expect(AudioSpecFormat.qualityFallback(requested: .lossless, actual: nil) == nil)
    }

    @Test func routeAndSourceLabelsAreStable() {
        #expect(AudioOutputPort.speaker.label == "Speaker")
        #expect(AudioOutputPort.headphones.label == "Headphones")
        #expect(AudioOutputPort.bluetooth.label == "Bluetooth")
        #expect(AudioOutputPort.usb.label == "USB")
        #expect(AudioOutputPort.airPlay.label == "AirPlay")
        #expect(AudioOutputPort.other.label == "Other")

        #expect(AudioPlaybackSource.stream.label == "Stream")
        #expect(AudioPlaybackSource.cache.label == "Cache")
        #expect(AudioPlaybackSource.download.label == "Download")
        #expect(AudioPlaybackSource.local.label == "Local file")
    }
}
