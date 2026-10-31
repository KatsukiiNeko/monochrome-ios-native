// EQSettingsStore.swift: tolerant JSON persistence for the equalizer state.
import Foundation

public struct EQState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var settings: EQSettings
    public var userPresets: [EQPreset]

    public init(
        schemaVersion: Int = EQState.currentSchemaVersion,
        settings: EQSettings = EQSettings(),
        userPresets: [EQPreset] = []
    ) {
        self.schemaVersion = schemaVersion
        self.settings = settings
        self.userPresets = userPresets
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, settings, userPresets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1,
            settings: try container.decodeIfPresent(EQSettings.self, forKey: .settings) ?? EQSettings(),
            userPresets: try container.decodeIfPresent([EQPreset].self, forKey: .userPresets) ?? []
        )
        userPresets = userPresets.map { preset in
            var copy = preset
            copy.group = .user
            copy.isBuiltIn = false
            return copy
        }
        if !EQPresetCatalog.all.contains(where: { $0.id == settings.selectedPresetID })
            && !userPresets.contains(where: { $0.id == settings.selectedPresetID }) {
            settings.selectedPresetID = EQPresetCatalog.flat.id
            settings.isPresetModified = true
        }
    }

    /// A trimmed, unique, length-limited user preset name.
    public func validatedName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else { return nil }
        guard !userPresets.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return nil
        }
        return name
    }
}

/// One small JSON file under Application Support. The caller excludes it from
/// backup. A corrupt file falls back to the default state and logs once.
public final class EQSettingsStore: @unchecked Sendable {
    private let fileURL: URL
    private let log: ((String) -> Void)?

    public init(fileURL: URL, log: ((String) -> Void)? = nil) {
        self.fileURL = fileURL
        self.log = log
    }

    public func load() -> EQState {
        guard let data = try? Data(contentsOf: fileURL) else {
            return EQState()
        }
        do {
            var state = try JSONDecoder().decode(EQState.self, from: data)
            state.settings.normalise()
            return state
        } catch {
            log?("eq state unreadable; using defaults error=\(error.localizedDescription)")
            return EQState()
        }
    }

    public func save(_ state: EQState) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(state).write(to: fileURL, options: .atomic)
        } catch {
            log?("eq state save failed error=\(error.localizedDescription)")
        }
    }
}
