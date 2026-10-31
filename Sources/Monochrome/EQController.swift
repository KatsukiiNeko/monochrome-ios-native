// EQController.swift: owns the equalizer state, its file and the preset catalog.
#if canImport(SwiftUI)
import Foundation
import MonochromeCore
import Observation

@MainActor
@Observable
final class EQController {
    private(set) var settings: EQSettings
    private(set) var userPresets: [EQPreset]
    /// What the current item can do, refreshed when playback state changes.
    private(set) var availability: EQAvailability = .available
    private(set) var isClipping = false
    private(set) var importSummary: EQImportSummary?

    let sampleRate: () -> Double
    private let store: EQSettingsStore
    private let player: PlayerController
    private let log: (String) -> Void
    private var clipTask: Task<Void, Never>?

    init(
        store: EQSettingsStore,
        player: PlayerController,
        sampleRate: @escaping () -> Double,
        log: @escaping (String) -> Void
    ) {
        self.store = store
        self.player = player
        self.sampleRate = sampleRate
        self.log = log
        let state = store.load()
        self.settings = state.settings
        self.userPresets = state.userPresets
    }

    /// Pushes the restored state into the engine, so the first item already
    /// starts with the saved curve.
    func activate() {
        player.setEqualizer(settings)
        refreshAvailability()
        startClipMonitor()
    }

    func refreshAvailability() {
        availability = player.eqAvailability
    }

    // MARK: - Groups and selection

    var monochromePresets: [EQPreset] { EQPresetCatalog.monochrome }
    var classicPresets: [EQPreset] { EQPresetCatalog.classic }

    var selectedPreset: EQPreset? {
        EQPresetCatalog.preset(id: settings.selectedPresetID)
            ?? userPresets.first { $0.id == settings.selectedPresetID }
    }

    var selectedPresetName: String { selectedPreset?.name ?? "Custom" }

    /// Stereo width does nothing without a second channel; the row is disabled
    /// for a mono item rather than pretending to act.
    var isMono: Bool { player.format?.channels == 1 }

    var isPresetModified: Bool { settings.isPresetModified }

    var currentFilters: [FilterSpec] { settings.effectiveFilters }

    // MARK: - Editing

    func setEnabled(_ isEnabled: Bool) {
        settings.isEnabled = isEnabled
        commit()
    }

    func setMode(_ mode: EQMode) {
        settings.mode = mode
        settings.isPresetModified = true
        commit()
    }

    func setGraphicGain(_ gain: Double, at index: Int) {
        guard settings.graphicGains.indices.contains(index) else { return }
        settings.graphicGains[index] = min(
            max((gain * 2).rounded() / 2, EQGraphicBands.minGainDB),
            EQGraphicBands.maxGainDB
        )
        settings.isPresetModified = true
        commit()
    }

    func addFilter() {
        guard settings.filters.count < EQSettings.maximumFilters else { return }
        settings.filters.append(FilterSpec(kind: .peak, frequency: 1_000, gainDB: 0, q: 1))
        settings.mode = .parametric
        settings.isPresetModified = true
        commit()
    }

    func removeFilter(id: UUID) {
        settings.filters.removeAll { $0.id == id }
        settings.isPresetModified = true
        commit()
    }

    func updateFilter(id: UUID, _ change: (inout FilterSpec) -> Void) {
        guard let index = settings.filters.firstIndex(where: { $0.id == id }) else { return }
        var spec = settings.filters[index]
        change(&spec)
        // Rebuild through the validating initializer so every edit stays in range.
        settings.filters[index] = FilterSpec(
            id: spec.id,
            kind: spec.kind,
            frequency: spec.frequency,
            gainDB: spec.gainDB,
            q: spec.q,
            enabled: spec.enabled
        )
        settings.mode = .parametric
        settings.isPresetModified = true
        commit()
    }

    func setPreampAuto(_ isAuto: Bool) {
        settings.autoPreamp = isAuto
        if !isAuto {
            settings.manualPreampDB = settings.preampDB(sampleRate: sampleRate())
        }
        commit()
    }

    func setManualPreamp(_ value: Double) {
        settings.autoPreamp = false
        settings.manualPreampDB = min(max(value, -24), 24)
        settings.isPresetModified = true
        commit()
    }

    func setBass(_ value: Double) {
        settings.bassDB = clamp(value, 0, 8)
        settings.isPresetModified = true
        commit()
    }

    func setClarity(_ value: Double) {
        settings.clarityDB = clamp(value, 0, 6)
        settings.isPresetModified = true
        commit()
    }

    func setStereoWidth(_ value: Double) {
        settings.stereoWidth = clamp(value, 0, 2)
        settings.isPresetModified = true
        commit()
    }

    func setDynamicBoost(_ value: Double) {
        settings.dynamicBoostDB = clamp(value, 0, 6)
        settings.isPresetModified = true
        commit()
    }

    // MARK: - Presets

    func apply(_ preset: EQPreset) {
        settings.apply(preset)
        commit()
    }

    func resetToPreset() {
        guard let preset = selectedPreset else { return }
        settings.apply(preset)
        commit()
    }

    func resetToFlat() {
        settings.apply(EQPresetCatalog.flat)
        settings.isEnabled = true
        commit()
    }

    /// Saves the current curve under a new name. Returns the reason when the
    /// name is rejected so the sheet can show it.
    @discardableResult
    func saveAs(name raw: String) -> String? {
        let state = EQState(settings: settings, userPresets: userPresets)
        guard let name = state.validatedName(raw) else {
            return "Use a unique name up to 40 characters."
        }
        var preset = EQPreset(
            id: "user.\(UUID().uuidString)",
            name: name,
            group: .user,
            graphicGains: settings.mode == .graphic ? settings.graphicGains : nil,
            filters: settings.mode == .parametric ? settings.filters : [],
            preampDB: settings.autoPreamp ? nil : settings.manualPreampDB,
            isBuiltIn: false
        )
        preset.isBuiltIn = false
        userPresets.append(preset)
        settings.selectedPresetID = preset.id
        settings.isPresetModified = false
        commit()
        return nil
    }

    func deletePreset(id: String) {
        guard userPresets.contains(where: { $0.id == id }) else { return }
        userPresets.removeAll { $0.id == id }
        if settings.selectedPresetID == id {
            settings.selectedPresetID = EQPresetCatalog.flat.id
            settings.isPresetModified = true
        }
        commit()
    }

    // MARK: - Import and export

    func importText(_ text: String) {
        let summary = EQTextFormat.parse(text)
        guard !summary.filters.isEmpty else {
            importSummary = summary
            return
        }
        settings.mode = .parametric
        settings.filters = summary.filters
        if let preamp = summary.preampDB {
            settings.autoPreamp = false
            settings.manualPreampDB = preamp
        }
        settings.selectedPresetID = EQPresetCatalog.flat.id
        settings.isPresetModified = true
        importSummary = summary
        commit()
        log("eq import filters=\(summary.applied) ignored=\(summary.ignored.count) clamped=\(summary.clamped.count)")
    }

    var exportText: String {
        EQTextFormat.export(
            filters: settings.effectiveFilters,
            preampDB: settings.autoPreamp ? nil : settings.manualPreampDB
        )
    }

    // MARK: - Persistence

    private func commit() {
        let state = EQState(settings: settings, userPresets: userPresets)
        store.save(state)
        player.setEqualizer(settings)
        refreshAvailability()
    }

    private func startClipMonitor() {
        clipTask?.cancel()
        clipTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { return }
                let peak = self.player.takeEqualizerPeak()
                let clipped = peak > 1
                if clipped != self.isClipping {
                    self.isClipping = clipped
                }
                self.refreshAvailability()
            }
        }
    }

    private func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        guard value.isFinite else { return low }
        return min(max(value, low), high)
    }
}
#endif
