// PlaylistImporter.swift: runs the search-match loop, one entry at a time,
// persisting progress so an interrupted import can resume.
import Foundation
import Observation

/// One entry's settled state, kept so progress is restorable.
public struct PlaylistImportSettlement: Codable, Equatable, Sendable, Identifiable {
    public var id: String {
        "\(entry.title)|\(entry.artist)"
    }

    public var entry: PlaylistImportEntry
    /// Chosen or auto-accepted track; nil while undecided or rejected.
    public var chosen: Track?
    public var wasRejected: Bool
    /// True when the matcher auto-accepted without human help.
    public var autoAccepted: Bool
    /// Best candidates kept when the matcher could not auto-accept.
    public var reviewCandidates: [Track]

    public init(
        entry: PlaylistImportEntry,
        chosen: Track? = nil,
        wasRejected: Bool = false,
        autoAccepted: Bool = false,
        reviewCandidates: [Track] = []
    ) {
        self.entry = entry
        self.chosen = chosen
        self.wasRejected = wasRejected
        self.autoAccepted = autoAccepted
        self.reviewCandidates = reviewCandidates
    }
}

public struct PlaylistImportProgress: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public var schemaVersion: Int
    public var playlistName: String
    public var pending: [PlaylistImportEntry]
    public var settled: [PlaylistImportSettlement]
    /// Searches that failed; reported so "review" entries are not blamed on the user.
    public var searchFailures: Int

    public init(
        playlistName: String,
        pending: [PlaylistImportEntry],
        settled: [PlaylistImportSettlement] = [],
        searchFailures: Int = 0
    ) {
        self.schemaVersion = Self.schemaVersion
        self.playlistName = playlistName
        self.pending = pending
        self.settled = settled
        self.searchFailures = searchFailures
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, playlistName, pending, settled, searchFailures
    }

    /// A file written before the version field existed migrates in place.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.schemaVersion
        playlistName = try container.decodeIfPresent(String.self, forKey: .playlistName) ?? "Imported Playlist"
        pending = try container.decodeIfPresent([PlaylistImportEntry].self, forKey: .pending) ?? []
        settled = try container.decodeIfPresent([PlaylistImportSettlement].self, forKey: .settled) ?? []
        searchFailures = try container.decodeIfPresent(Int.self, forKey: .searchFailures) ?? 0
    }
}

/// Injectable catalog search so host tests run without network.
public typealias PlaylistSearch = @Sendable (String) async throws -> [Track]

@MainActor
@Observable
public final class PlaylistImporter {
    public static let maxEntries = 500
    /// Sequential searches, at least a quarter second apart.
    static let searchSpacing: TimeInterval = 0.25
    static let progressMaxBytes = 4 * 1024 * 1024

    public private(set) var playlistName = ""
    public private(set) var total = 0
    public private(set) var processed = 0
    public private(set) var isRunning = false
    /// Entries still awaiting the search loop; drains as it runs.
    public private(set) var pendingEntries: [PlaylistImportEntry] = []
    public private(set) var settlements: [PlaylistImportSettlement] = []
    public private(set) var searchFailures = 0

    private var search: PlaylistSearch?
    private var store: JSONFileStore?
    private var task: Task<Void, Never>?

    public init() {}

    static func makeStore(_ fileURL: URL) -> JSONFileStore {
        JSONFileStore(fileURL: fileURL, maxBytes: progressMaxBytes, log: nil)
    }

    /// Saved progress for an unfinished run, if any.
    public static func storedProgress(at fileURL: URL) -> PlaylistImportProgress? {
        makeStore(fileURL).read(PlaylistImportProgress.self)
    }

    // MARK: - Running

    /// Starts a fresh import, replacing any stored progress. Truncates past the
    /// cap and reports the drop through the returned count.
    @discardableResult
    public func start(
        name: String,
        entries: [PlaylistImportEntry],
        search: @escaping PlaylistSearch,
        store fileURL: URL
    ) -> Int {
        cancel()
        removeProgressFile(at: fileURL)
        let capped = Array(entries.prefix(Self.maxEntries))
        playlistName = name.isEmpty ? "Imported Playlist" : name
        total = capped.count
        processed = 0
        searchFailures = 0
        pendingEntries = capped
        settlements = []
        isRunning = true
        self.search = search
        store = Self.makeStore(fileURL)
        runLoop()
        return entries.count - capped.count
    }

    /// Restores a saved, unfinished run instead of starting over.
    @discardableResult
    public func resume(store fileURL: URL, search: @escaping PlaylistSearch) -> Bool {
        guard task == nil, !isRunning else { return false }
        guard let progress = Self.makeStore(fileURL).read(PlaylistImportProgress.self),
              !progress.pending.isEmpty else { return false }
        playlistName = progress.playlistName
        total = progress.pending.count + progress.settled.count
        processed = progress.settled.count
        pendingEntries = progress.pending
        settlements = progress.settled
        searchFailures = progress.searchFailures
        isRunning = true
        self.search = search
        store = Self.makeStore(fileURL)
        runLoop()
        return true
    }

    public func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// Stops after the current entry; progress stays on disk for `resume`.
    public func pause() {
        cancel()
    }

    public func discardProgress(fileURL: URL) {
        cancel()
        removeProgressFile(at: fileURL)
        pendingEntries = []
        settlements = []
    }

    private func removeProgressFile(at fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func runLoop() {
        task = Task { [weak self] in
            await self?.processPending()
        }
    }

    private func processPending() async {
        while let entry = pendingEntries.first, !Task.isCancelled {
            pendingEntries.removeFirst()
            await settle(entry)
            processed += 1
            persist()
            do {
                try await Task.sleep(for: .milliseconds(Int(Self.searchSpacing * 1000)))
            } catch {
                break // cancelled between entries
            }
        }
        isRunning = false
        task = nil
    }

    private func settle(_ entry: PlaylistImportEntry) async {
        // The app's own snapshots skip the network entirely.
        if let snapshot = entry.snapshot {
            settlements.append(PlaylistImportSettlement(entry: entry, chosen: snapshot, autoAccepted: true))
            return
        }
        guard let search else {
            settlements.append(PlaylistImportSettlement(entry: entry))
            return
        }
        do {
            let candidates = try await search(PlaylistMatcher.searchQuery(for: entry))
            let outcome = PlaylistMatcher.match(entry: entry, candidates: candidates)
            if let accepted = outcome.accepted {
                settlements.append(PlaylistImportSettlement(
                    entry: entry,
                    chosen: accepted.candidate,
                    autoAccepted: true
                ))
            } else {
                // Undecided for now; the review UI picks one of the candidates.
                settlements.append(PlaylistImportSettlement(
                    entry: entry,
                    reviewCandidates: outcome.reviewCandidates.map(\.candidate)
                ))
            }
        } catch {
            searchFailures += 1
            settlements.append(PlaylistImportSettlement(entry: entry))
        }
    }

    private func persist() {
        guard let store else { return }
        try? store.write(PlaylistImportProgress(
            playlistName: playlistName,
            pending: pendingEntries,
            settled: settlements,
            searchFailures: searchFailures
        ))
    }

    // MARK: - Review

    /// Entries with no chosen track and no rejection, in order.
    public var reviewEntries: [PlaylistImportSettlement] {
        settlements.filter { $0.chosen == nil && !$0.wasRejected }
    }

    public func choose(_ settlement: PlaylistImportSettlement, track: Track) {
        guard let index = settlements.firstIndex(where: { $0.entry == settlement.entry }) else { return }
        settlements[index].chosen = track
        persist()
    }

    public func reject(_ settlement: PlaylistImportSettlement) {
        guard let index = settlements.firstIndex(where: { $0.entry == settlement.entry }) else { return }
        settlements[index].wasRejected = true
        persist()
    }

    public var chosenTracks: [Track] {
        settlements.compactMap { $0.wasRejected ? nil : $0.chosen }
    }

    public var summary: String {
        "\(chosenTracks.count) matched, \(reviewEntries.count) need review, \(searchFailures) searches failed"
    }
}
