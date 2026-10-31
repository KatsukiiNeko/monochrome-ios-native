// EQSettings.swift: the equalizer state shared by the player, the store and the UI.
import Foundation

public enum EQMode: String, Codable, CaseIterable, Sendable {
    case graphic
    case parametric
}

/// Everything the equalizer needs to rebuild its processing chain.
public struct EQSettings: Codable, Equatable, Sendable {
    public static let maximumFilters = 16

    public var isEnabled: Bool
    public var mode: EQMode
    public var graphicGains: [Double]
    public var filters: [FilterSpec]
    public var selectedPresetID: String
    public var isPresetModified: Bool
    public var autoPreamp: Bool
    public var manualPreampDB: Double
    public var bassDB: Double
    public var clarityDB: Double
    public var stereoWidth: Double
    public var dynamicBoostDB: Double

    public init(
        isEnabled: Bool = false,
        mode: EQMode = .graphic,
        graphicGains: [Double] = Array(repeating: 0, count: EQGraphicBands.frequencies.count),
        filters: [FilterSpec] = [],
        selectedPresetID: String = "flat",
        isPresetModified: Bool = false,
        autoPreamp: Bool = true,
        manualPreampDB: Double = 0,
        bassDB: Double = 0,
        clarityDB: Double = 0,
        stereoWidth: Double = 1,
        dynamicBoostDB: Double = 0
    ) {
        self.isEnabled = isEnabled
        self.mode = mode
        self.graphicGains = graphicGains
        self.filters = filters
        self.selectedPresetID = selectedPresetID
        self.isPresetModified = isPresetModified
        self.autoPreamp = autoPreamp
        self.manualPreampDB = manualPreampDB
        self.bassDB = bassDB
        self.clarityDB = clarityDB
        self.stereoWidth = stereoWidth
        self.dynamicBoostDB = dynamicBoostDB
        normalise()
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, mode, graphicGains, filters, selectedPresetID
        case isPresetModified, autoPreamp, manualPreampDB
        case bassDB, clarityDB, stereoWidth, dynamicBoostDB
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false,
            mode: try container.decodeIfPresent(EQMode.self, forKey: .mode) ?? .graphic,
            graphicGains: try container.decodeIfPresent([Double].self, forKey: .graphicGains)
                ?? Array(repeating: 0, count: EQGraphicBands.frequencies.count),
            filters: try container.decodeIfPresent([FilterSpec].self, forKey: .filters) ?? [],
            selectedPresetID: try container.decodeIfPresent(String.self, forKey: .selectedPresetID) ?? "flat",
            isPresetModified: try container.decodeIfPresent(Bool.self, forKey: .isPresetModified) ?? false,
            autoPreamp: try container.decodeIfPresent(Bool.self, forKey: .autoPreamp) ?? true,
            manualPreampDB: try container.decodeIfPresent(Double.self, forKey: .manualPreampDB) ?? 0,
            bassDB: try container.decodeIfPresent(Double.self, forKey: .bassDB) ?? 0,
            clarityDB: try container.decodeIfPresent(Double.self, forKey: .clarityDB) ?? 0,
            stereoWidth: try container.decodeIfPresent(Double.self, forKey: .stereoWidth) ?? 1,
            dynamicBoostDB: try container.decodeIfPresent(Double.self, forKey: .dynamicBoostDB) ?? 0
        )
    }

    /// Clamps every value and pads the graphic bands. Called after decoding so a
    /// hand-edited or older file cannot put the DSP out of range.
    public mutating func normalise() {
        if graphicGains.count < EQGraphicBands.frequencies.count {
            graphicGains += Array(
                repeating: 0,
                count: EQGraphicBands.frequencies.count - graphicGains.count
            )
        }
        if graphicGains.count > EQGraphicBands.frequencies.count {
            graphicGains = Array(graphicGains.prefix(EQGraphicBands.frequencies.count))
        }
        graphicGains = graphicGains.map {
            guard $0.isFinite else { return 0 }
            return min(max($0, EQGraphicBands.minGainDB), EQGraphicBands.maxGainDB)
        }
        filters = Array(filters.prefix(Self.maximumFilters))
        manualPreampDB = Self.clamp(manualPreampDB, -24, 24)
        bassDB = Self.clamp(bassDB, 0, 8)
        clarityDB = Self.clamp(clarityDB, 0, 6)
        stereoWidth = Self.clamp(stereoWidth, 0, 2)
        dynamicBoostDB = Self.clamp(dynamicBoostDB, 0, 6)
    }

    /// The bands the tap actually runs: the active mode plus the effect sliders.
    public var effectiveFilters: [FilterSpec] {
        var result: [FilterSpec]
        switch mode {
        case .graphic:
            result = EQGraphicBands.filters(gains: graphicGains)
        case .parametric:
            result = filters.filter(\.enabled)
        }
        if bassDB != 0 {
            result.append(FilterSpec(kind: .lowShelf, frequency: 100, gainDB: bassDB, q: 0.7071))
        }
        if clarityDB != 0 {
            result.append(FilterSpec(kind: .highShelf, frequency: 6_000, gainDB: clarityDB, q: 0.7071))
            result.append(FilterSpec(kind: .peak, frequency: 3_000, gainDB: clarityDB / 2, q: 1))
        }
        return Array(result.prefix(24))
    }

    /// The preamp in dB, from Auto or the manual override.
    public func preampDB(sampleRate: Double) -> Double {
        autoPreamp
            ? EQResponse.autoPreampDB(filters: effectiveFilters, sampleRate: sampleRate)
            : manualPreampDB
    }

    /// True when the chain would change nothing; the tap is then not attached.
    public var isFlat: Bool {
        effectiveFilters.isEmpty
            && preampDB(sampleRate: 48_000) == 0
            && stereoWidth == 1
            && dynamicBoostDB == 0
    }

    /// Applies a built-in or user preset and clears the effect sliders.
    public mutating func apply(_ preset: EQPreset) {
        selectedPresetID = preset.id
        isPresetModified = false
        autoPreamp = preset.preampDB == nil
        manualPreampDB = preset.preampDB ?? 0
        bassDB = 0
        clarityDB = 0
        stereoWidth = 1
        dynamicBoostDB = 0
        if let gains = preset.graphicGains {
            mode = .graphic
            graphicGains = gains
            filters = []
        } else {
            mode = .parametric
            filters = preset.filters.map {
                FilterSpec(
                    kind: $0.kind,
                    frequency: $0.frequency,
                    gainDB: $0.gainDB,
                    q: $0.q,
                    enabled: $0.enabled
                )
            }
        }
        normalise()
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        guard value.isFinite else { return low }
        return min(max(value, low), high)
    }

    /// Whether the current curve still equals the preset it was selected from.
    /// Effects and preamp are part of the comparison, so moving a slider marks
    /// the selection as modified.
    public func matches(_ preset: EQPreset) -> Bool {
        guard bassDB == 0, clarityDB == 0, stereoWidth == 1, dynamicBoostDB == 0 else {
            return false
        }
        if let gains = preset.graphicGains {
            guard mode == .graphic, gains.count == graphicGains.count else { return false }
            return zip(gains, graphicGains).allSatisfy { abs($0 - $1) < 0.001 }
        }
        guard mode == .parametric, filters.count == preset.filters.count else { return false }
        return zip(filters, preset.filters).allSatisfy { left, right in
            left.kind == right.kind
                && abs(left.frequency - right.frequency) < 0.001
                && abs(left.gainDB - right.gainDB) < 0.001
                && abs(left.q - right.q) < 0.001
                && left.enabled == right.enabled
        }
    }
}
