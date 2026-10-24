// AudioInfoLineTests.swift: host tests for the ordered audio-summary variants.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("AudioInfoLine")
struct AudioInfoLineTests {
    private func spec(
        codec: String? = "flac",
        sampleRateHz: Int? = 44_100,
        bitDepth: Int? = 16,
        quality: AudioQuality? = .lossless,
        source: AudioPlaybackSource = .stream
    ) -> AudioSpec {
        AudioSpec(
            codec: codec,
            sampleRateHz: sampleRateHz,
            bitDepth: bitDepth,
            qualityRequested: quality,
            source: source,
            provenance: [.codec: .measured, .sampleRate: .measured, .bitDepth: .measured]
        )
    }

    @Test func theFullVariantLeadsWithFormatThenDetailThenStatus() {
        let variants = AudioInfoLine.variants(spec: spec(), source: .cache, isDownloaded: false)

        #expect(variants.count == 3)
        #expect(variants[0].map(\.text) == ["FLAC 16/44.1", "16-bit / 44.1 kHz", "Cached"])
        #expect(variants[0].map(\.kind) == [.format, .detail, .status])
        #expect(variants[1].map(\.text) == ["FLAC 16/44.1", "16-bit / 44.1 kHz"])
        #expect(variants[2].map(\.text) == ["FLAC 16/44.1"])
    }

    @Test func variantsDropDetailFromTheEndAndKeepTheLeadingFormat() {
        let variants = AudioInfoLine.variants(
            spec: spec(),
            source: .download,
            isDownloaded: true
        )

        #expect(variants.map(\.count) == [3, 2, 1])
        #expect(variants.allSatisfy { $0 == Array(variants[0].prefix($0.count)) })
    }

    @Test func aSpecWithoutFormatOrQualityFallsBackToADetailOnlyChip() {
        let variants = AudioInfoLine.variants(
            spec: spec(codec: nil, quality: nil),
            source: .stream,
            isDownloaded: false
        )

        #expect(variants.map { $0.map(\.text) } == [["16-bit / 44.1 kHz"]])
    }

    @Test func aFormatWithoutSampleRateStillCarriesTheKnownBitDepth() {
        let variants = AudioInfoLine.variants(
            spec: spec(codec: "flac", sampleRateHz: nil, bitDepth: 24, quality: nil),
            source: .stream,
            isDownloaded: false
        )

        #expect(variants.map { $0.map(\.text) } == [["FLAC", "24-bit"], ["FLAC"]])
    }

    @Test func anEmptySpecHasNoChips() {
        let variants = AudioInfoLine.variants(
            spec: AudioSpec(source: .local),
            source: .local,
            isDownloaded: false
        )
        #expect(variants.isEmpty)
    }

    @Test func downloadedAndCachedStatesAreLabelledAndSpoken() {
        let downloaded = AudioInfoLine.variants(
            spec: spec(source: .download),
            source: .download,
            isDownloaded: true
        )
        let cached = AudioInfoLine.variants(
            spec: spec(source: .cache),
            source: .cache,
            isDownloaded: false
        )

        let downloadStatus = downloaded[0].last
        #expect(downloadStatus?.text == "Downloaded")
        #expect(downloadStatus?.kind == .status)
        #expect(downloadStatus?.spokenText == "Playing from a permanent download")

        let cacheStatus = cached[0].last
        #expect(cacheStatus?.text == "Cached")
        #expect(cacheStatus?.spokenText == "Playing from the local cache")
    }

    @Test func theDownloadedFlagWinsOverAStaleCacheSource() {
        let variants = AudioInfoLine.variants(
            spec: spec(source: .cache),
            source: .cache,
            isDownloaded: true
        )
        #expect(variants[0].last?.text == "Downloaded")
    }

    @Test func spokenDetailExpandsTheSampleRateUnit() {
        #expect(AudioSpecFormat.spokenDetail(for: spec()) == "16-bit, 44.1 kilohertz")
        #expect(AudioSpecFormat.spokenDetail(for: AudioSpec(bitDepth: 24, source: .stream)) == "24-bit")
        #expect(AudioSpecFormat.spokenDetail(for: AudioSpec(source: .stream)) == nil)
    }

    @Test func repeatedCallsProduceTheSameVariants() {
        let first = AudioInfoLine.variants(spec: spec(), source: .cache, isDownloaded: false)
        let second = AudioInfoLine.variants(spec: spec(), source: .cache, isDownloaded: false)
        #expect(first == second)
    }
}
