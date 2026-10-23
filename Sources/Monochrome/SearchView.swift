// SearchView.swift: debounced catalog search for tracks, albums and artists.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct SearchView: View {
    let model: AppModel

    @State private var query = ""
    @State private var tracks: [Track] = []
    @State private var releases: [RemoteRelease] = []
    @State private var artists: [RemoteArtist] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selectedRelease: RemoteRelease?
    @State private var selectedArtist: RemoteArtist?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if !tracks.isEmpty { tracksSection }
                    if !releases.isEmpty { releasesSection }
                    if !artists.isEmpty { artistsSection }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 24)
            }
            .background(Color(white: 0.05).ignoresSafeArea())
            .overlay { stateOverlay }
            .task(id: query) { await runSearch() }
            .navigationTitle("Search")
            .sheet(item: $selectedRelease) { release in
                ReleaseDetailView(model: model, release: release)
            }
            .sheet(item: $selectedArtist) { artist in
                ArtistDetailView(model: model, artist: artist)
            }
        }
        // Owned by the navigation container so the drawer is visible on entry,
        // rather than following the scroll view's content offset.
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Tracks, artists, albums"
        )
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasResults: Bool {
        !tracks.isEmpty || !releases.isEmpty || !artists.isEmpty
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if !model.isStreamingConfigured {
            ContentUnavailableView {
                Label("Streaming is off", systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text("Choose a streaming host in Settings to search the catalog.")
            }
        } else if isSearching {
            ProgressView("Searching…")
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Search failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Retry") { Task { await runSearch(force: true) } }
            }
        } else if trimmedQuery.isEmpty {
            ContentUnavailableView {
                Label("Search the catalog", systemImage: "magnifyingglass")
            } description: {
                Text("Find tracks, albums and artists by name.")
            }
        } else if !hasResults {
            ContentUnavailableView.search(text: trimmedQuery)
        }
    }

    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Tracks")
            ForEach(tracks) { track in
                Button {
                    Task { await model.play(track, in: tracks) }
                } label: {
                    TrackRow(
                        track: track,
                        isCurrent: model.player.currentTrack?.id == track.id
                    )
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var releasesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Albums")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(releases) { release in
                        Button {
                            selectedRelease = release
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                TrackArtwork(
                                    track: Track(
                                        title: release.title,
                                        artist: release.artist,
                                        artworkURL: release.artworkURL
                                    ),
                                    cornerRadius: 10
                                )
                                .frame(width: 140, height: 140)
                                Text(release.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text(release.artist)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 140, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Album \(release.title) by \(release.artist)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var artistsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Artists")
            ForEach(artists) { artist in
                Button {
                    selectedArtist = artist
                } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: artist.avatarURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Circle().fill(Color(white: 0.14))
                            }
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                        .accessibilityHidden(true)

                        Text(artist.name)
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Artist \(artist.name)")
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
    }

    private func runSearch(force: Bool = false) async {
        let text = trimmedQuery
        guard text.count >= 2 else {
            tracks = []
            releases = []
            artists = []
            errorMessage = nil
            isSearching = false
            return
        }
        if !force {
            // Debounce. SwiftUI cancels this task when the query changes, and the
            // cancellation checks below drop the stale response.
            try? await Task.sleep(for: .milliseconds(300))
        }
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }
        do {
            async let foundTracks = model.searchTracks(text)
            async let foundReleases = model.searchReleases(text)
            async let foundArtists = model.searchArtists(text)
            let (tracks, releases, artists) = try await (foundTracks, foundReleases, foundArtists)
            guard !Task.isCancelled else { return }
            self.tracks = tracks
            self.releases = releases
            self.artists = artists
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            tracks = []
            releases = []
            artists = []
            errorMessage = error.localizedDescription
        }
    }
}
#endif
