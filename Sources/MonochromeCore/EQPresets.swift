// EQPresets.swift: the built-in Monochrome and classic ten-band catalogs.
import Foundation

public enum EQPresetGroup: String, Codable, Sendable {
    case monochrome
    case classic
    case user
}

public struct EQPreset: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var group: EQPresetGroup
    /// Ten-band presets are applied in graphic mode.
    public var graphicGains: [Double]?
    /// Parametric presets are applied band by band.
    public var filters: [FilterSpec]
    /// Imported presets can carry their own preamp; built-ins use Auto.
    public var preampDB: Double?
    public var isBuiltIn: Bool

    public init(
        id: String,
        name: String,
        group: EQPresetGroup,
        graphicGains: [Double]? = nil,
        filters: [FilterSpec] = [],
        preampDB: Double? = nil,
        isBuiltIn: Bool = true
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.graphicGains = graphicGains
        self.filters = filters
        self.preampDB = preampDB
        self.isBuiltIn = isBuiltIn
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, group, graphicGains, filters, preampDB, isBuiltIn
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            name: try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled",
            group: try container.decodeIfPresent(EQPresetGroup.self, forKey: .group) ?? .user,
            graphicGains: try container.decodeIfPresent([Double].self, forKey: .graphicGains),
            filters: try container.decodeIfPresent([FilterSpec].self, forKey: .filters) ?? [],
            preampDB: try container.decodeIfPresent(Double.self, forKey: .preampDB),
            isBuiltIn: false
        )
    }
}

public enum EQPresetCatalog {
    public static let flat = EQPreset(
        id: "mono.flat",
        name: "Flat",
        group: .monochrome
    )

    public static let monochrome: [EQPreset] = [
        flat,
        parametric("mono.bassBoost", "Bass Boost", [
            (.lowShelf, 110, 5, 0.71),
            (.peak, 250, -1, 0.9),
        ]),
        parametric("mono.bassReducer", "Bass Reducer", [
            (.lowShelf, 120, -5, 0.71),
        ]),
        parametric("mono.trebleBoost", "Treble Boost", [
            (.highShelf, 5_000, 4, 0.71),
            (.peak, 3_000, 1, 1),
        ]),
        parametric("mono.trebleReducer", "Treble Reducer", [
            (.highShelf, 6_000, -4, 0.71),
        ]),
        parametric("mono.vocalBoost", "Vocal Boost", [
            (.peak, 250, -2, 1),
            (.peak, 3_000, 3, 1),
            (.highShelf, 9_000, 1.5, 0.71),
        ]),
        parametric("mono.loudness", "Loudness", [
            (.lowShelf, 100, 5, 0.71),
            (.highShelf, 8_000, 3.5, 0.71),
        ]),
        parametric("mono.rock", "Rock", [
            (.lowShelf, 90, 3.5, 0.71),
            (.peak, 400, -2.5, 0.8),
            (.peak, 3_500, 2, 1),
            (.highShelf, 9_000, 3, 0.71),
        ]),
        parametric("mono.pop", "Pop", [
            (.lowShelf, 100, 2, 0.71),
            (.peak, 300, -1.5, 1),
            (.peak, 2_500, 2.5, 1),
            (.highShelf, 9_000, 2, 0.71),
        ]),
        parametric("mono.hipHop", "Hip-Hop", [
            (.lowShelf, 80, 6, 0.71),
            (.peak, 300, -2, 0.9),
            (.peak, 3_000, 1.5, 1),
            (.highShelf, 10_000, 1.5, 0.71),
        ]),
        parametric("mono.electronic", "Electronic", [
            (.lowShelf, 70, 4.5, 0.71),
            (.peak, 450, -2, 0.8),
            (.highShelf, 8_000, 4, 0.71),
        ]),
        parametric("mono.rnb", "R&B / Soul", [
            (.lowShelf, 90, 4, 0.71),
            (.peak, 350, -1.5, 1),
            (.peak, 2_800, 1.5, 1),
            (.highShelf, 10_000, 1.5, 0.71),
        ]),
        parametric("mono.acoustic", "Acoustic", [
            (.peak, 150, 1.5, 0.9),
            (.peak, 3_500, 2, 1),
            (.highShelf, 9_000, 2, 0.71),
        ]),
        parametric("mono.jazz", "Jazz", [
            (.lowShelf, 110, 2.5, 0.71),
            (.peak, 2_500, 1, 1),
            (.highShelf, 8_000, 2, 0.71),
        ]),
        parametric("mono.classical", "Classical", [
            (.lowShelf, 100, 1, 0.71),
            (.peak, 3_000, 1, 0.8),
            (.highShelf, 10_000, 1.5, 0.71),
        ]),
        parametric("mono.lounge", "Lounge", [
            (.lowShelf, 110, 2, 0.71),
            (.highShelf, 7_000, -3, 0.71),
        ]),
        parametric("mono.spokenWord", "Spoken Word", [
            (.highPass, 80, 0, 0.71),
            (.peak, 250, -2, 1),
            (.peak, 3_000, 3.5, 0.9),
            (.highShelf, 8_000, -1.5, 0.71),
        ]),
        parametric("mono.smallSpeakers", "Small Speakers", [
            (.highPass, 100, 0, 0.71),
            (.peak, 200, 3.5, 0.9),
            (.peak, 3_500, 2, 1),
        ]),
        parametric("mono.reference", "Reference (Harman-inspired)", [
            (.lowShelf, 105, 4, 0.71),
            (.peak, 250, -1, 0.9),
            (.peak, 3_000, 1, 1),
            (.highShelf, 10_000, -1.5, 0.71),
        ]),
        parametric("mono.referenceLight", "Reference, lighter bass", [
            (.lowShelf, 105, -2.5, 0.71),
            (.peak, 3_000, 1, 1),
            (.highShelf, 10_000, -1, 0.71),
        ]),
    ]

    public static let classic: [EQPreset] = [
        graphic("classic.classical", "Classical", [0, 0, 0, 0, 0, 0, 0, -1.7, -4, -5]),
        graphic("classic.club", "Club", [0, 0, 0, 1.3, 2.7, 3, 3, 2.6, 1.2, 0]),
        graphic("classic.dance", "Dance", [5, 4.9, 3.9, 1.9, 0.3, 0, -1.9, -3.4, -4, 0]),
        graphic("classic.fullBass", "Full Bass", [2.9, 3, 3.7, 2.9, 1.7, 0, 0, 0, 0, 0]),
        graphic("classic.fullTreble", "Full Treble", [-5, -5, -5, -5, -3.2, 1.5, 4, 6.5, 8, 8.5]),
        graphic("classic.fullBassTreble", "Full Bass + Treble", [3.5, 3.5, 3.1, 1.1, -2.9, -2.5, -0.3, 2.5, 4.9, 6]),
        graphic("classic.laptop", "Laptop/Headphones", [2.5, 2.6, 4.3, 3.4, -0.8, 0, -1.9, -3.4, -4, 0]),
        graphic("classic.largeHall", "Large Hall", [5, 5, 5, 3.7, 3, 0, -1.6, -2.5, -2.5, 0]),
        graphic("classic.live", "Live", [-2.5, -2.4, -0.7, 1.3, 2.4, 3, 3, 2.6, 1.8, 1]),
        graphic("classic.party", "Party", [3.5, 3.5, 3.5, 1.3, 0, 0, 0, 0, 0, 3.5]),
        graphic("classic.pop", "Pop", [-1, -0.8, 1.5, 3.1, 3.9, 2.5, 0.6, -0.9, -1.5, -1]),
        graphic("classic.reggae", "Reggae", [0, 0, 0, -0.3, -2.3, 0, -2.2, -3.5, -2, 0]),
        graphic("classic.rock", "Rock", [4, 3.9, 2.9, -1, -3.7, -2, 0.5, 3, 4.9, 5.5]),
        graphic("classic.soft", "Soft", [2.5, 2.4, 1.4, 0, -1.2, -0.5, 1.1, 3, 4.7, 6]),
        graphic("classic.ska", "Ska", [-1.5, -1.5, -2.2, -2.5, -1.1, 2, 2.6, 3.6, 4.7, 5]),
        graphic("classic.softRock", "Soft Rock", [2, 2, 2, 1.4, -0.1, -2.5, -2.8, -2.6, -1.4, 4.5]),
        graphic("classic.techno", "Techno", [4, 4, 3.3, 1.1, -2.2, -2.5, -0.9, 1.7, 4.4, 4.5]),
    ]

    public static var all: [EQPreset] { monochrome + classic }

    public static func preset(id: String) -> EQPreset? {
        all.first { $0.id == id }
    }

    private static func parametric(
        _ id: String,
        _ name: String,
        _ bands: [(BiquadKind, Double, Double, Double)]
    ) -> EQPreset {
        EQPreset(
            id: id,
            name: name,
            group: .monochrome,
            filters: bands.map { kind, frequency, gain, q in
                FilterSpec(kind: kind, frequency: frequency, gainDB: gain, q: q)
            }
        )
    }

    private static func graphic(_ id: String, _ name: String, _ gains: [Double]) -> EQPreset {
        EQPreset(id: id, name: name, group: .classic, graphicGains: gains)
    }
}
