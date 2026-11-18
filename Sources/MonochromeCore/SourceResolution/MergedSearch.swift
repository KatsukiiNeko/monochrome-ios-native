// MergedSearch.swift: one result list from the two sources, HiFi rows first.
import Foundation

public enum MergedSearchPhase: String, Equatable, Sendable {
    /// Neither source has answered yet.
    case pending
    /// One source has answered or given up; the list can be shown.
    case partial
    /// Every configured source has answered.
    case complete
    /// Nothing could be answered.
    case failed
}

public enum MergedSideStatus: String, Equatable, Sendable {
    case pending
    case complete
    case failed
    /// The source has no server yet, so it takes no part in the search.
    case unconfigured
}

public struct MergedSearchResults: Equatable, Sendable {
    public var hifi: [Track]
    /// Companion rows that no HiFi row already covers.
    public var companion: [Track]
    public var hifiStatus: MergedSideStatus
    public var companionStatus: MergedSideStatus

    public init(
        hifi: [Track] = [],
        companion: [Track] = [],
        hifiStatus: MergedSideStatus = .pending,
        companionStatus: MergedSideStatus = .pending
    ) {
        self.hifi = hifi
        self.companion = companion
        self.hifiStatus = hifiStatus
        self.companionStatus = companionStatus
    }

    /// HiFi rows keep their order and are never moved by a companion result.
    public var rows: [Track] { hifi + companion }

    public var phase: MergedSearchPhase {
        if hifiStatus == .failed, companionStatus == .failed { return .failed }
        if isResolved(hifiStatus), isResolved(companionStatus) { return .complete }
        if hifiStatus == .pending, companionStatus == .pending { return .pending }
        return .partial
    }

    /// The empty state appears only when both sources finished with nothing.
    public var isEmpty: Bool { rows.isEmpty && phase == .complete }

    /// Shown quietly beside the results, never instead of them.
    public var quietNote: String? {
        if hifiStatus == .failed, companionStatus == .failed {
            return "Search is unavailable."
        }
        if hifiStatus == .failed { return "HiFi results are unavailable." }
        if companionStatus == .failed { return "YouTube Music results are unavailable." }
        return nil
    }

    private func isResolved(_ status: MergedSideStatus) -> Bool {
        status == .complete || status == .unconfigured
    }
}

public enum MergedSearch {
    /// A companion source that takes longer than this is left for the next search.
    public static let companionMergeBudget: Duration = .seconds(3)

    public static func merge(
        hifi: [Track],
        companion: [Track],
        hifiStatus: MergedSideStatus = .complete,
        companionStatus: MergedSideStatus = .complete,
        matcher: TrackMatcher = TrackMatcher()
    ) -> MergedSearchResults {
        var uniqueCompanion: [Track] = []
        for track in companion {
            let covered = hifi.contains { matcher.isMatch(track, $0) }
                || uniqueCompanion.contains { matcher.isMatch(track, $0) }
            if !covered { uniqueCompanion.append(track) }
        }
        return MergedSearchResults(
            hifi: hifi,
            companion: uniqueCompanion,
            hifiStatus: hifiStatus,
            companionStatus: companionStatus
        )
    }

    /// Runs both searches at once and waits for the companion only inside the
    /// budget. A late companion result is dropped so rows never move after the
    /// list is shown. A nil companion closure means the source has no server.
    public static func collect(
        hifi: @escaping @Sendable () async throws -> [Track],
        companion: (@Sendable () async throws -> [Track])?,
        budget: Duration = companionMergeBudget,
        matcher: TrackMatcher = TrackMatcher()
    ) async -> MergedSearchResults {
        let hifiTask = Task { try? await hifi() }
        guard let companion else {
            let tracks = await hifiTask.value
            return merge(
                hifi: tracks ?? [],
                companion: [],
                hifiStatus: tracks == nil ? .failed : .complete,
                companionStatus: .unconfigured,
                matcher: matcher
            )
        }

        enum SideOutcome: Sendable {
            case tracks([Track])
            case failed
            case timedOut
        }

        let companionTask = Task { try? await companion() }
        let outcome = await withTaskGroup(of: SideOutcome.self) { group in
            group.addTask {
                guard let tracks = await companionTask.value else { return .failed }
                return .tracks(tracks)
            }
            group.addTask {
                try? await Task.sleep(for: budget)
                companionTask.cancel()
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }

        let hifiTracks = await hifiTask.value
        let companionTracks: [Track]
        let companionStatus: MergedSideStatus
        switch outcome {
        case .tracks(let tracks):
            companionTracks = tracks
            companionStatus = .complete
        case .failed:
            companionTracks = []
            companionStatus = .failed
        case .timedOut:
            // Stop the search too; a result after the budget would move rows.
            companionTask.cancel()
            companionTracks = []
            companionStatus = .failed
        }
        return merge(
            hifi: hifiTracks ?? [],
            companion: companionTracks,
            hifiStatus: hifiTracks == nil ? .failed : .complete,
            companionStatus: companionStatus,
            matcher: matcher
        )
    }
}
