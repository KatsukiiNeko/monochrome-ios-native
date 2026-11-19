// MusicSource.swift: stable source identity and what each source can actually do.
import Foundation

public struct SourceCapabilities: OptionSet, Sendable, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let search = SourceCapabilities(rawValue: 1 << 0)
    public static let stream = SourceCapabilities(rawValue: 1 << 1)
    public static let downloads = SourceCapabilities(rawValue: 1 << 2)
}

public enum MusicSourceID: String, Codable, CaseIterable, Sendable, Equatable {
    case monochrome
    case youTubeMusic
    /// Episodes stream from the feed's own audio URL; the app stores no copy.
    case podcast

    public var displayName: String {
        switch self {
        case .monochrome: "Monochrome (HiFi)"
        case .youTubeMusic: "YouTube Music (companion server)"
        case .podcast: "Podcasts"
        }
    }

    public var capabilities: SourceCapabilities {
        switch self {
        case .monochrome:
            // The upstream web client downloads the same progressive FLAC stream:
            // js/api.js:3050 and js/downloads.js:348 in the upstream tree.
            [.search, .stream, .downloads]
        case .youTubeMusic:
            [.search, .stream]
        case .podcast:
            [.stream]
        }
    }

    public var supportsDownloads: Bool {
        capabilities.contains(.downloads)
    }

    public var downloadUnavailableReason: String {
        "Downloads are not available for this source."
    }
}

extension Track {
    /// Local files are not a remote source; they use the default source identity
    /// only so old records can decode without a new stored field.
    public var source: MusicSourceID {
        MusicSourceID(rawValue: provider) ?? .monochrome
    }
}
