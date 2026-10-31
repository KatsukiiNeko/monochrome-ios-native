// EQPresetTests.swift: the equalizer settings model and the preset catalog.
import Foundation
import Testing
@testable import MonochromeCore

@Test func defaultStateIsFlatAndOff() {
    let settings = EQSettings()
    #expect(!settings.isEnabled)
    #expect(settings.mode == .graphic)
    #expect(settings.graphicGains.count == 10)
    #expect(settings.graphicGains.allSatisfy { $0 == 0 })
    #expect(settings.effectiveFilters.isEmpty)
    #expect(settings.isFlat)
    #expect(settings.preampDB(sampleRate: 48_000) == 0)
}

@Test func normaliseClampsEveryValue() {
    var settings = EQSettings(
        graphicGains: [99, -99],
        filters: (0..<40).map { _ in FilterSpec(kind: .peak, frequency: 1_000, gainDB: 3) },
        manualPreampDB: 100,
        bassDB: 90,
        clarityDB: -3,
        stereoWidth: 9,
        dynamicBoostDB: 90
    )
    settings.normalise()
    #expect(settings.graphicGains.count == 10)
    #expect(settings.graphicGains.first == 12)
    #expect(settings.graphicGains[1] == -12)
    #expect(settings.filters.count == EQSettings.maximumFilters)
    #expect(settings.manualPreampDB == 24)
    #expect(settings.bassDB == 8)
    #expect(settings.clarityDB == 0)
    #expect(settings.stereoWidth == 2)
    #expect(settings.dynamicBoostDB == 6)
}

@Test func decodedSettingsTolerateMissingFields() throws {
    let json = #"{"isEnabled":true,"mode":"parametric","filters":[{"kind":"lowShelf","frequency":80,"gainDB":4}]}"#
    let settings = try JSONDecoder().decode(EQSettings.self, from: Data(json.utf8))
    #expect(settings.isEnabled)
    #expect(settings.mode == .parametric)
    #expect(settings.filters.count == 1)
    #expect(settings.filters[0].kind == .lowShelf)
    #expect(settings.graphicGains.count == 10)
    #expect(settings.stereoWidth == 1)
}

@Test func applyingAParametricPresetClearsEffectsAndMarksSelection() {
    var settings = EQSettings(bassDB: 4, clarityDB: 2, stereoWidth: 1.5, dynamicBoostDB: 3)
    let preset = EQPresetCatalog.preset(id: "mono.rock")!
    settings.apply(preset)

    #expect(settings.selectedPresetID == "mono.rock")
    #expect(settings.mode == .parametric)
    #expect(!settings.isPresetModified)
    #expect(settings.bassDB == 0)
    #expect(settings.clarityDB == 0)
    #expect(settings.stereoWidth == 1)
    #expect(settings.dynamicBoostDB == 0)
    #expect(settings.filters.count == preset.filters.count)
    #expect(settings.filters[0].id != preset.filters[0].id)
}

@Test func applyingAClassicPresetUsesTheGraphicBands() {
    var settings = EQSettings()
    let preset = EQPresetCatalog.preset(id: "classic.rock")!
    settings.apply(preset)

    #expect(settings.mode == .graphic)
    #expect(settings.graphicGains == preset.graphicGains)
    #expect(settings.filters.isEmpty)
    #expect(settings.effectiveFilters.count == 10)
}

@Test func everyBuiltInPresetHasNonPositiveHeadroomAfterPreamp() {
    for preset in EQPresetCatalog.all {
        var settings = EQSettings()
        settings.apply(preset)
        let filters = settings.effectiveFilters
        let preamp = settings.preampDB(sampleRate: 48_000)
        let peak = EQResponse.peakDB(filters: filters, sampleRate: 48_000) + preamp
        #expect(peak <= 0.011, "\(preset.name): \(peak) dB")
    }
}

/// Composite gain at the ISO centers for the built-in catalog, from the
/// reference table the presets were designed against.
private let catalogCenters: [String: [Double]] = [
    "mono.flat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    "mono.bassBoost": [4.9, 4.4, 1.5, -0.8, -0.3, -0.1, 0, 0, 0, 0],
    "mono.bassReducer": [-5.0, -4.6, -2.3, -0.3, 0, 0, 0, 0, 0, 0],
    "mono.trebleBoost": [0, 0, 0, 0, 0, 0.1, 0.7, 1.9, 3.7, 4.0],
    "mono.trebleReducer": [0, 0, 0, 0, 0, 0, 0, -0.6, -3.2, -4.0],
    "mono.vocalBoost": [0, -0.1, -0.6, -2.0, -0.5, 0.2, 1.7, 2.2, 0.9, 1.5],
    "mono.loudness": [5.0, 4.3, 1.5, 0.1, 0, 0, 0, 0.2, 1.7, 3.5],
    "mono.rock": [3.4, 2.7, 0.3, -1.5, -2.2, -0.5, 0.7, 1.9, 1.4, 3.0],
    "mono.pop": [2.0, 1.7, 0.3, -1.2, -0.6, 0.3, 2.0, 1.3, 0.9, 2.0],
    "mono.hipHop": [5.8, 4.2, 0.4, -1.7, -1.0, -0.1, 0.8, 1.1, 0.6, 1.5],
    "mono.electronic": [4.3, 2.6, 0.2, -1.0, -1.9, -0.7, -0.2, 0.1, 2.0, 4.0],
    "mono.rnb": [3.9, 3.2, 0.6, -0.9, -0.9, 0, 1.0, 1.0, 0.5, 1.5],
    "mono.acoustic": [0.1, 0.4, 1.4, 0.8, 0.2, 0.2, 0.8, 1.9, 1.1, 2.0],
    "mono.jazz": [2.5, 2.3, 0.9, 0.1, 0, 0.2, 0.8, 0.6, 1.1, 2.0],
    "mono.classical": [1.0, 0.9, 0.3, 0, 0, 0.2, 0.7, 0.8, 0.6, 1.5],
    "mono.lounge": [2.0, 1.8, 0.7, 0.1, 0, 0, 0, -0.2, -2.0, -3.0],
    "mono.spokenWord": [-16.3, -5.7, -1.3, -2.0, -0.5, 0.4, 2.2, 2.6, -0.2, -1.4],
    "mono.smallSpeakers": [-20.0, -8.2, 0.5, 2.9, 0.8, 0.4, 0.9, 1.9, 0.4, 0],
    "mono.reference": [3.9, 3.5, 1.0, -0.9, -0.3, 0, 0.6, 0.7, -0.2, -1.4],
    "mono.referenceLight": [-2.5, -2.2, -0.8, -0.1, 0, 0.1, 0.6, 0.7, -0.1, -1.0],
]

@Test func monochromePresetsMatchTheirPublishedCurves() {
    let centers: [Double] = [31.5, 63, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    for preset in EQPresetCatalog.monochrome {
        guard let expected = catalogCenters[preset.id] else {
            Issue.record("missing reference curve for \(preset.id)")
            continue
        }
        var settings = EQSettings()
        settings.apply(preset)
        let filters = settings.effectiveFilters
        for (frequency, gain) in zip(centers, expected) {
            let measured = EQResponse.magnitudeDB(filters: filters, at: frequency, sampleRate: 48_000)
            #expect(
                abs(measured - gain) < 0.1,
                "\(preset.name) at \(frequency) Hz: \(measured) vs \(gain)"
            )
        }
    }
}

@Test func catalogHasNoDuplicateIDsAndExpectedGroups() {
    let ids = EQPresetCatalog.all.map(\.id)
    #expect(Set(ids).count == ids.count)
    #expect(EQPresetCatalog.monochrome.count == 20)
    #expect(EQPresetCatalog.classic.count == 17)
    #expect(EQPresetCatalog.all.allSatisfy { $0.isBuiltIn })
    #expect(EQPresetCatalog.flat.id == "mono.flat")
}

@Test func effectsAreAppendedToTheActiveChain() {
    var settings = EQSettings(bassDB: 4, clarityDB: 3)
    let filters = settings.effectiveFilters
    #expect(filters.count == 3)
    #expect(filters.contains { $0.kind == .lowShelf && $0.frequency == 100 && $0.gainDB == 4 })
    #expect(filters.contains { $0.kind == .highShelf && $0.frequency == 6_000 && $0.gainDB == 3 })
    #expect(filters.contains { $0.kind == .peak && $0.frequency == 3_000 && $0.gainDB == 1.5 })
    #expect(!settings.isFlat)

    settings.bassDB = 0
    settings.clarityDB = 0
    #expect(settings.isFlat)
}
