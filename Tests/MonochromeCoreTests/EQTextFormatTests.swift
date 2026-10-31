// EQTextFormatTests.swift: import, export and availability rules.
import Foundation
import Testing
@testable import MonochromeCore

// MARK: - Import and export

private let sampleEQ = """
Preamp: -6.4 dB
Filter 1: ON LS Fc 105 Hz Gain 3.8 dB Q 0.70
Filter 2: ON PK Fc 127 Hz Gain -2.4 dB Q 0.70
Filter 3: ON HS Fc 10000 Hz Gain -3.6 dB Q 0.70
"""

@Test func importParsesTheCanonicalFormat() {
    let summary = EQTextFormat.parse(sampleEQ)
    #expect(summary.applied == 3)
    #expect(summary.preampDB == -6.4)
    #expect(summary.ignored.isEmpty)
    #expect(summary.filters[0].kind == .lowShelf)
    #expect(summary.filters[1].kind == .peak)
    #expect(summary.filters[2].kind == .highShelf)
    #expect(abs(summary.filters[2].frequency - 10_000) < 1e-9)
}

@Test func importToleratesNoiseClampingAndTruncation() {
    let text = """
    # comment

    Preamp: 12,5 dB
    this line is not a filter
    Filter 1: OFF PK Fc 10 Hz Gain 40 dB Q 99
    Filter 2: ON LS Fc 120 Hz Gain -3 dB S 1.0
    Filter 3: ON HS Fc 9000 Hz Gain 2 dB Q 0.7
    Filter 4: ON PK Fc 1000 Hz Gain 0 dB Q 1
    """
    let summary = EQTextFormat.parse(text, maxFilters: 3)
    #expect(summary.applied == 3)
    #expect(summary.truncated == 1)
    #expect(summary.ignored.count == 1)
    #expect(summary.preampDB == 12.5)
    #expect(summary.filters[0].frequency == 20)
    #expect(summary.filters[0].gainDB == 15)
    #expect(summary.filters[0].q == 10)
    #expect(!summary.filters[0].enabled)
    #expect(!summary.clamped.isEmpty)
}

@Test func slopeBecomesAUsableQ() {
    let summary = EQTextFormat.parse("Filter 1: ON LS Fc 100 Hz Gain 6 dB S 1.0")
    #expect(abs(summary.filters[0].q - 0.7071) < 0.05)
}

@Test func exportThenImportIsAFixedPoint() {
    let filters = [
        FilterSpec(kind: .peak, frequency: 1_000, gainDB: 6, q: 1),
        FilterSpec(kind: .lowShelf, frequency: 105, gainDB: 3.5, q: 0.71),
        FilterSpec(kind: .highShelf, frequency: 8_000, gainDB: -2.5, q: 0.71, enabled: false),
    ]
    let text = EQTextFormat.export(filters: filters, preampDB: -4.5)
    let summary = EQTextFormat.parse(text)

    #expect(summary.applied == 3)
    #expect(summary.preampDB == -4.5)
    for (original, restored) in zip(filters, summary.filters) {
        #expect(original.kind == restored.kind)
        #expect(original.enabled == restored.enabled)
        #expect(abs(original.frequency - restored.frequency) < 0.1)
        #expect(abs(original.gainDB - restored.gainDB) < 0.1)
        #expect(abs(original.q - restored.q) < 0.01)
    }
}

@Test func availabilityRejectsHLSAndMissingTracks() {
    #expect(EQAvailability.isHLS(url: URL(string: "https://x/y.m3u8")!, contentType: nil))
    #expect(EQAvailability.isHLS(url: URL(string: "https://x/y")!, contentType: "application/vnd.apple.mpegurl"))
    #expect(
        EQAvailability.resolve(url: URL(string: "https://x/y.flac")!, contentType: "audio/flac", hasAudioTrack: true)
            == .available
    )
    #expect(
        EQAvailability.resolve(url: URL(string: "https://x/y.m3u8")!, contentType: nil, hasAudioTrack: true)
            == .unavailable(.hls)
    )
    #expect(
        EQAvailability.resolve(url: URL(string: "https://x/y.flac")!, contentType: nil, hasAudioTrack: false)
            == .unavailable(.noAudioTrack)
    )
}
