// SourceSelectionService.swift: reject wrong recordings, then rank by quality and priority.
import Foundation

public struct SourceCandidate: Equatable, Sendable {
    public var providerID: String
    public var track: Track
    public var quality: AudioQuality?

    public init(providerID: String, track: Track, quality: AudioQuality? = nil) {
        self.providerID = providerID
        self.track = track
        self.quality = quality ?? track.audioQuality
    }

    public var qualityRank: Int { (quality ?? track.audioQuality)?.rank ?? 0 }
}

public struct SourceSelectionService: Sendable {
    public init() {}

    /// Returns eligible candidates in preference order: quality tier first, then
    /// provider priority. Wrong recordings are removed before any comparison.
    public func select(
        requested: Track,
        candidates: [SourceCandidate],
        providerPriority: [String],
        matcher: TrackMatcher = TrackMatcher()
    ) -> [SourceCandidate] {
        let eligible = candidates.filter { matcher.isMatch($0.track, requested) }
        return eligible.sorted { lhs, rhs in
            if lhs.qualityRank != rhs.qualityRank { return lhs.qualityRank > rhs.qualityRank }
            let leftIndex = providerPriority.firstIndex(of: lhs.providerID) ?? Int.max
            let rightIndex = providerPriority.firstIndex(of: rhs.providerID) ?? Int.max
            if leftIndex != rightIndex { return leftIndex < rightIndex }
            return lhs.providerID < rhs.providerID
        }
    }
}