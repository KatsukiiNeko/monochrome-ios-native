// MusicSourceProvider.swift: one boundary between the app and a music source.
import Foundation

/// What a provider can do. A provider is a source of tracks and playback sources,
/// not a UI concern.
public struct ProviderCapabilities: OptionSet, Sendable, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let search = ProviderCapabilities(rawValue: 1 << 0)
    public static let browse = ProviderCapabilities(rawValue: 1 << 1)
    public static let audio = ProviderCapabilities(rawValue: 1 << 2)
    public static let lyrics = ProviderCapabilities(rawValue: 1 << 3)
    public static let radio = ProviderCapabilities(rawValue: 1 << 4)
}

/// Normalized provider failures. The UI maps these to one-line status text.
public enum ProviderError: Error, Equatable, Sendable, LocalizedError {
    case notConfigured
    case unavailable
    case rateLimited(retryAfter: TimeInterval?)
    case unauthorized
    case transient(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: "Not configured."
        case .unavailable: "Unavailable."
        case .rateLimited(let retry): retry.map { "Rate limited; retry after \(Int($0))s." } ?? "Rate limited."
        case .unauthorized: "Unauthorized."
        case .transient(let reason): reason
        }
    }
}

/// A provider supplies tracks and resolves one to a playback source. The player
/// depends on this protocol, never on a concrete catalog client.
public protocol MusicSourceProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var capabilities: ProviderCapabilities { get }

    func search(_ query: String, limit: Int) async throws -> [Track]
    func resolve(_ track: Track) async throws -> PlaybackSource
}

extension AudioQuality {
    /// Higher is better for ranking candidates. Unknown tiers sort last.
    public var rank: Int {
        switch self {
        case .hiResLossless: 5
        case .lossless: 4
        case .dolbyAtmos: 3
        case .high: 2
        case .low: 1
        case .lossy: 1
        }
    }
}