// EQSettingsStoreTests.swift: persistence, tolerant decoding and user presets.
import Foundation
import Testing
@testable import MonochromeCore

private func temporaryFile(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("eq-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent(name)
}

@Test func storeRoundTripsAndClamps() {
    let url = temporaryFile("eq.json")
    let store = EQSettingsStore(fileURL: url)
    var settings = EQSettings(isEnabled: true, mode: .parametric, bassDB: 5)
    settings.filters = [FilterSpec(kind: .peak, frequency: 1_000, gainDB: 6, q: 1)]
    let state = EQState(settings: settings, userPresets: [
        EQPreset(id: "user.1", name: "Mine", group: .user, filters: settings.filters, isBuiltIn: false),
    ])
    store.save(state)

    let loaded = EQSettingsStore(fileURL: url).load()
    #expect(loaded.settings.isEnabled)
    #expect(loaded.settings.mode == .parametric)
    #expect(loaded.settings.bassDB == 5)
    #expect(loaded.userPresets.map(\.name) == ["Mine"])
    #expect(loaded.userPresets[0].isBuiltIn == false)
}

@Test func corruptStateFallsBackToDefaults() throws {
    let url = temporaryFile("eq.json")
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("not json".utf8).write(to: url)
    var logged = false
    let store = EQSettingsStore(fileURL: url) { _ in logged = true }
    let state = store.load()
    #expect(state.settings == EQSettings())
    #expect(logged)
}

@Test func unknownPresetFallsBackToFlat() throws {
    let url = temporaryFile("eq.json")
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let json = #"{"schemaVersion":1,"settings":{"selectedPresetID":"gone.preset","filters":[]}}"#
    try Data(json.utf8).write(to: url)
    let state = EQSettingsStore(fileURL: url).load()
    #expect(state.settings.selectedPresetID == "mono.flat")
    #expect(state.settings.isPresetModified)
}

@Test func userPresetNamesAreValidated() {
    let state = EQState(userPresets: [
        EQPreset(id: "user.1", name: "Warm", group: .user, isBuiltIn: false),
    ])
    #expect(state.validatedName("  Warm  ") == nil)
    #expect(state.validatedName("warm") == nil)
    #expect(state.validatedName("   ") == nil)
    #expect(state.validatedName(String(repeating: "x", count: 41)) == nil)
    #expect(state.validatedName("  New preset ") == "New preset")
}

