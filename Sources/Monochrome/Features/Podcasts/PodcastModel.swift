// PodcastModel.swift: podcast search, show lookup and episode playback.
#if canImport(SwiftUI)
import Foundation
import MonochromeCore
import Observation

/// Owns the podcast directory client for the views. Episodes play through the
/// existing player as ordinary streamable tracks.
@MainActor
@Observable
final class PodcastModel {
    @ObservationIgnored private let client: PodcastsAPIClient
    @ObservationIgnored private let player: PlayerController

    var query = ""
    private(set) var shows: [RemotePodcast] = []
    private(set) var episodes: [PodcastEpisode] = []
    private(set) var selectedShow: RemotePodcast?
    private(set) var isSearching = false
    private(set) var isLoadingEpisodes = false
    private(set) var errorMessage: String?

    init(player: PlayerController, client: PodcastsAPIClient = PodcastsAPIClient()) {
        self.player = player
        self.client = client
    }

    /// Searches after the same short pause the song search uses; SwiftUI
    /// cancels this task when the query changes again.
    func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            shows = []
            errorMessage = nil
            isSearching = false
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            shows = try await client.searchPodcasts(matching: text)
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            shows = []
            errorMessage = error.localizedDescription
        }
    }

    /// Loads the episodes of a show; the show stays selected even when the
    /// feed cannot be read, so the error has a place to show.
    func open(_ show: RemotePodcast) async {
        selectedShow = show
        episodes = []
        errorMessage = nil
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }
        do {
            episodes = try await client.episodes(for: show)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func closeShow() {
        selectedShow = nil
        episodes = []
        errorMessage = nil
    }

    /// Plays an episode inside the context of its show.
    func play(_ episode: PodcastEpisode) {
        guard let show = selectedShow else { return }
        let tracks = episodes.map { $0.track(show: show) }
        guard let index = tracks.firstIndex(where: { $0.id == "podcast:\(episode.id)" }) else { return }
        Task { await player.play(tracks: tracks, startingAt: index) }
    }
}
#endif
