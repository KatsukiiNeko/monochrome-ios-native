// RadioEngine.swift: a radio that grows the queue from a seed.
import Foundation
import Observation

/// Where a radio starts from.
public enum RadioSeed: Equatable, Sendable {
    case track(Track)
    case artist(String)
    case album(String)

    /// The text the catalog is asked for.
    public var query: String {
        switch self {
        case .track(let track):
            track.artist.isEmpty ? track.title : track.artist
        case .artist(let name):
            name
        case .album(let name):
            name
        }
    }
}

/// Finds more tracks for a radio.
public typealias RadioSearch = (String) async throws -> [Track]

/// Keeps a radio running. It remembers its seed, asks the catalog for more
/// tracks and never repeats what was played recently.
@MainActor
@Observable
public final class RadioEngine {
    /// New tracks are added when this few are left in the queue.
    public static let topUpThreshold = 3
    /// How many recent plays are remembered and skipped.
    public static let recentPlayMemory = 50
    /// How many tracks one top-up adds.
    public static let topUpSize = 20

    public private(set) var seed: RadioSeed?
    public private(set) var isRunning = false
    public private(set) var lastError: String?
    /// The tracks this radio put in the queue.
    public private(set) var ownTrackKeys: Set<String> = []

    @ObservationIgnored private let search: RadioSearch
    @ObservationIgnored private let recentKeys: () -> [String]

    public init(search: @escaping RadioSearch, recentKeys: @escaping () -> [String]) {
        self.search = search
        self.recentKeys = recentKeys
    }

    /// True when the queue is low enough to need more tracks.
    public static func needsTopUp(remaining: Int) -> Bool {
        remaining <= topUpThreshold
    }

    /// Starts a radio and returns the tracks for the first queue; a track seed
    /// stays first.
    public func start(seed: RadioSeed) async -> [Track] {
        self.seed = seed
        isRunning = true
        lastError = nil
        ownTrackKeys = []
        var opening: [Track] = []
        if case .track(let track) = seed {
            ownTrackKeys.insert(track.sourceKey)
            opening = [track]
            // A seed without a stream cannot be played from a queue.
            if track.streamID == nil, !track.isStreaming { opening = [] }
        }
        let candidates = await fetch(seed.query)
        let tracks = opening + pick(candidates, excluding: [])
        ownTrackKeys.formUnion(tracks.map(\.sourceKey))
        return tracks
    }

    /// Adds tracks when the queue runs low and returns the ones to append.
    public func topUp(queued: [Track]) async -> [Track] {
        guard isRunning, let seed else { return [] }
        let candidates = await fetch(seed.query)
        let tracks = pick(candidates, excluding: queued.map(\.sourceKey))
        ownTrackKeys.formUnion(tracks.map(\.sourceKey))
        return tracks
    }

    /// Ends the radio; the queue stays as it is.
    public func stop() {
        isRunning = false
        seed = nil
        ownTrackKeys = []
    }

    /// True when the track belongs to this radio.
    public func owns(_ track: Track) -> Bool {
        ownTrackKeys.contains(track.sourceKey)
    }

    /// Drops the tracks that were played recently, that are already queued or
    /// that the radio already used.
    private func pick(_ candidates: [Track], excluding queuedKeys: [String]) -> [Track] {
        let recent = Set(recentKeys().suffix(Self.recentPlayMemory))
        let known = Set(queuedKeys).union(ownTrackKeys)
        var result: [Track] = []
        for track in candidates where !recent.contains(track.sourceKey) && !known.contains(track.sourceKey) {
            result.append(track)
            if result.count >= Self.topUpSize { break }
        }
        return result
    }

    private func fetch(_ query: String) async -> [Track] {
        guard !query.isEmpty else { return [] }
        do {
            return try await search(query)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }
}
