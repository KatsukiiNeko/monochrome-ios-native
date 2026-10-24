// SearchView.swift: pinned catalog search with recent searches, chips and a top result.
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
    @State private var filter: SearchResultKind = .all
    @State private var selectedRelease: RemoteRelease?
    @State private var selectedArtist: RemoteArtist?
    @State private var pendingDownloadRemoval: DownloadItem?
    @Environment(\.accentColor) private var accent
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.vertical, 8)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                        if trimmedQuery.isEmpty {
                            if !model.searchRecents.isEmpty { recentSearchesSection }
                        } else if isSearching && !hasResults {
                            loadingPlaceholder
                        } else {
                            resultsContent
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, 24)
                }
                .background(Theme.background)
                .overlay { stateOverlay }
                .task(id: query) { await runSearch() }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Search")
            .sheet(item: $selectedRelease) { release in
                ReleaseDetailView(model: model, release: release)
            }
            .sheet(item: $selectedArtist) { artist in
                ArtistDetailView(model: model, artist: artist)
            }
            .confirmationDialog(
                "Remove “\(pendingDownloadRemoval?.track.title ?? "this download")”?",
                isPresented: Binding(
                    get: { pendingDownloadRemoval != nil },
                    set: { if !$0 { pendingDownloadRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove download", role: .destructive) {
                    guard let item = pendingDownloadRemoval else { return }
                    pendingDownloadRemoval = nil
                    Task { await model.removeDownload(item) }
                }
                Button("Cancel", role: .cancel) { pendingDownloadRemoval = nil }
            } message: {
                Text("The offline copy is deleted. You can download it again later.")
            }
        }
    }

    /// Pinned above the results instead of living in the navigation drawer, so
    /// scrolling can never hide it.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(isSearchFocused ? accent : Theme.secondaryText)
            TextField("Songs, artists, albums", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)
                .tint(accent)
                .accessibilityLabel("Search songs, artists and albums")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.tertiaryText)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(isSearchFocused ? accent : Theme.border, lineWidth: Theme.hairline)
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasResults: Bool {
        !tracks.isEmpty || !releases.isEmpty || !artists.isEmpty
    }

    private var availableKinds: [SearchResultKind] {
        SearchResults.availableKinds(
            hasTracks: !tracks.isEmpty,
            hasReleases: !releases.isEmpty,
            hasArtists: !artists.isEmpty
        )
    }

    private var activeFilter: SearchResultKind {
        availableKinds.contains(filter) ? filter : .all
    }

    private var sections: SearchResultSections {
        SearchResults.apply(
            activeFilter,
            tracks: tracks,
            releases: releases,
            artists: artists
        )
    }

    @ViewBuilder
    private var resultsContent: some View {
        if !availableKinds.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableKinds) { kind in
                        Chip(title: kind.title, isSelected: activeFilter == kind) {
                            filter = kind
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }

        if activeFilter == .all {
            topResultSection
        }
        if !sections.tracks.isEmpty {
            tracksSection
        }
        if !sections.releases.isEmpty {
            releasesSection
        }
        if !sections.artists.isEmpty {
            artistsSection
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if !model.isStreamingConfigured {
            ContentUnavailableView {
                Label("Streaming is off", systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text("Enable the endpoint in Settings to search the catalog.")
            }
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Search failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Retry") { Task { await runSearch(force: true) } }
            }
        } else if !isSearching, trimmedQuery.isEmpty, model.searchRecents.isEmpty {
            ContentUnavailableView {
                Label("Search the catalog", systemImage: "magnifyingglass")
            } description: {
                Text("Find songs, albums and artists by name.")
            }
        } else if !isSearching, !trimmedQuery.isEmpty, !hasResults {
            ContentUnavailableView.search(text: trimmedQuery)
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: Theme.rowSpacing) {
                    RoundedRectangle(cornerRadius: Theme.artworkRadius)
                        .fill(Theme.surface)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.surface)
                            .frame(width: 180, height: 12)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Theme.surface)
                            .frame(width: 120, height: 10)
                    }
                    Spacer()
                }
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Searching")
    }

    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShelfHeader(title: "Recent searches", actionTitle: "Clear all") {
                model.clearSearchRecents()
            }
            ForEach(Array(model.searchRecents.enumerated()), id: \.element.id) { index, track in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: Theme.hairline)
                        .padding(.leading, 64)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 8) {
                    Button {
                        play(track, in: model.searchRecents)
                    } label: {
                        TrackRow(
                            track: track,
                            isCurrent: model.player.currentTrack?.id == track.id
                        )
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        model.removeSearchRecent(track)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Delete \(track.title) from recent searches")
                }
            }
        }
    }

    @ViewBuilder
    private var topResultSection: some View {
        if let track = sections.tracks.first {
            topResult(track)
        } else if let release = sections.releases.first {
            topResult(release)
        } else if let artist = sections.artists.first {
            topResult(artist)
        }
    }

    private func topResult(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ShelfHeader(title: "Top result")
            Button {
                play(track, in: sections.tracks)
            } label: {
                HStack(spacing: 12) {
                    TrackArtwork(
                        track: track,
                        localURL: model.artworkURL(for: track),
                        cornerRadius: Theme.albumRadius
                    )
                    .frame(width: 76, height: 76)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(2)
                        Text(track.displayArtist)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.primaryText)
                        .accessibilityHidden(true)
                }
                .padding(10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .stroke(Theme.border, lineWidth: Theme.hairline)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Top result: \(track.title) by \(track.displayArtist)")
            .accessibilityHint("Plays this track")
        }
    }

    private func topResult(_ release: RemoteRelease) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ShelfHeader(title: "Top result")
            Button {
                selectedRelease = release
            } label: {
                HStack(spacing: 12) {
                    TrackArtwork(
                        track: Track(
                            title: release.title,
                            artist: release.artist,
                            artworkURL: release.artworkURL
                        ),
                        cornerRadius: Theme.albumRadius
                    )
                    .frame(width: 76, height: 76)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(release.title)
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(2)
                        Text("Album · \(release.artist)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
                .padding(10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .stroke(Theme.border, lineWidth: Theme.hairline)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Top result: album \(release.title) by \(release.artist)")
            .accessibilityHint("Opens album")
        }
    }

    private func topResult(_ artist: RemoteArtist) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ShelfHeader(title: "Top result")
            Button {
                selectedArtist = artist
            } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: artist.avatarURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Circle().fill(Theme.elevated)
                        }
                    }
                    .frame(width: 76, height: 76)
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(artist.name)
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(2)
                        Text("Artist")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
                .padding(10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .stroke(Theme.border, lineWidth: Theme.hairline)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Top result: artist \(artist.name)")
            .accessibilityHint("Opens artist")
        }
    }

    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShelfHeader(title: "Songs")
            ForEach(Array(sections.tracks.enumerated()), id: \.element.id) { index, track in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: Theme.hairline)
                        .padding(.leading, 64)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 0) {
                    Button {
                        play(track, in: sections.tracks)
                    } label: {
                        TrackRow(
                            track: track,
                            isCurrent: model.player.currentTrack?.id == track.id,
                            showsKind: true
                        )
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    trackMenu(track)
                }
            }
        }
    }

    private func trackMenu(_ track: Track) -> some View {
        Menu {
            if model.player.currentTrack != nil {
                Button("Add to queue", systemImage: "text.badge.plus") {
                    model.player.append([track])
                }
            }
            Button(
                model.isFavorite(track) ? "Remove from favorites" : "Add to favorites",
                systemImage: model.isFavorite(track) ? "heart.slash" : "heart"
            ) {
                model.toggleFavorite(track)
            }
            if track.source.supportsDownloads {
                Divider()
                downloadAction(track)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More actions for \(track.title)")
    }

    @ViewBuilder
    private func downloadAction(_ track: Track) -> some View {
        if let state = model.downloadState(for: track) {
            switch state {
            case .completed:
                Button("Remove download", systemImage: "trash", role: .destructive) {
                    pendingDownloadRemoval = model.downloads.first {
                        $0.track.id == track.id && $0.state == .completed
                    }
                }
            case .queued, .downloading:
                Label("Downloading…", systemImage: "arrow.down.circle")
            case .failed:
                Button("Retry download", systemImage: "arrow.clockwise") {
                    model.startDownload(track)
                }
            case .cancelled:
                Button("Download", systemImage: "arrow.down.circle") {
                    model.startDownload(track)
                }
            }
        } else {
            Button("Download", systemImage: "arrow.down.circle") {
                model.startDownload(track)
            }
        }
    }

    private var releasesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShelfHeader(title: "Albums")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(sections.releases) { release in
                        ArtworkTile(
                            track: Track(
                                title: release.title,
                                artist: release.artist,
                                artworkURL: release.artworkURL
                            ),
                            width: 140,
                            accessibilityLabel: "Album \(release.title) by \(release.artist)",
                            accessibilityHint: "Opens album"
                        ) {
                            selectedRelease = release
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var artistsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShelfHeader(title: "Artists")
            ForEach(sections.artists) { artist in
                Button {
                    selectedArtist = artist
                } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: artist.avatarURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Circle().fill(Theme.elevated)
                            }
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                        .accessibilityHidden(true)

                        Text(artist.name)
                            .font(Theme.rowTitle)
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Artist \(artist.name)")
            }
        }
    }

    private func play(_ track: Track, in results: [Track]) {
        Task {
            model.recordSearch(track)
            await model.play(track, in: results)
        }
    }

    private func runSearch(force: Bool = false) async {
        filter = .all
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
