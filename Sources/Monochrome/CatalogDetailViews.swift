// CatalogDetailViews.swift: album and artist sheets that load real catalog detail.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct ReleaseDetailView: View {
    let model: AppModel
    let release: RemoteRelease

    @Environment(\.dismiss) private var dismiss
    @State private var detail: RemoteReleaseDetail?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowInsets(EdgeInsets(
                            top: 8,
                            leading: Theme.screenPadding,
                            bottom: 12,
                            trailing: Theme.screenPadding
                        ))
                        .listRowBackground(Color.clear)
                }

                Section {
                    if let detail {
                        ForEach(detail.tracks) { track in
                            Button {
                                Task { await model.play(track, in: detail.tracks) }
                            } label: {
                                TrackRow(
                                    track: track,
                                    isCurrent: model.player.currentTrack?.id == track.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    TechnicalSectionHeader(
                        title: "Tracks",
                        meta: detail.map { "\($0.tracks.count) TRACKS" }
                    )
                }
            }
            .listStyle(.plain)
            .listRowSeparatorTint(Theme.separator)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .overlay { stateOverlay }
            .navigationTitle(release.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.primaryText)
                }
            }
            .task { await load() }
        }
    }

    private var shownRelease: RemoteRelease { detail?.release ?? release }

    /// The first four digits of a catalog date, when the host sends one.
    private var yearLabel: String? {
        guard let date = shownRelease.releaseDate,
              date.count >= 4,
              date.prefix(4).allSatisfy(\.isNumber) else { return nil }
        return String(date.prefix(4))
    }

    private var summary: String {
        var parts: [String] = []
        if let yearLabel { parts.append(yearLabel) }
        if let count = shownRelease.trackCount {
            parts.append(count == 1 ? "1 TRACK" : "\(count) TRACKS")
        }
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                TrackArtwork(
                    track: Track(
                        title: shownRelease.title,
                        artist: shownRelease.artist,
                        artworkURL: shownRelease.artworkURL
                    ),
                    cornerRadius: Theme.albumRadius
                )
                .frame(width: 108, height: 108)

                VStack(alignment: .leading, spacing: 4) {
                    Text(shownRelease.title)
                        .font(Theme.sectionTitle)
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    Text(shownRelease.artist)
                        .font(Theme.rowSubtitle)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                    if !summary.isEmpty {
                        TechnicalLabel(text: summary)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    Task { await play(shuffled: false) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(Theme.listRowTitle)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primaryAction)
                .foregroundStyle(Theme.onPrimaryAction)
                .disabled(!hasTracks)
                .accessibilityHint("Plays this album in order")

                Button {
                    Task { await play(shuffled: true) }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(Theme.listRowTitle)
                }
                .glassControlStyle()
                .disabled(!hasTracks)
                .accessibilityHint("Plays this album in a random order")
            }
        }
    }

    private var hasTracks: Bool { !(detail?.tracks.isEmpty ?? true) }

    /// Shuffle starts on a random track and pins it, so the first song is not
    /// always track one.
    private func play(shuffled: Bool) async {
        guard let detail, !detail.tracks.isEmpty else { return }
        let index = shuffled ? Int.random(in: 0..<detail.tracks.count) : 0
        await model.play(detail.tracks[index], in: detail.tracks)
        if shuffled, !model.player.isShuffled {
            model.player.toggleShuffle()
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if isLoading, detail == nil {
            ProgressView("Loading album…")
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Album unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Retry") { Task { await load() } }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await model.releaseDetail(id: release.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ArtistDetailView: View {
    let model: AppModel
    let artist: RemoteArtist

    @Environment(\.dismiss) private var dismiss
    @Environment(RadioModel.self) private var radio
    @State private var detail: RemoteArtistDetail?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var selectedRelease: RemoteRelease?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        AsyncImage(url: artist.avatarURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Circle().fill(Theme.elevated)
                            }
                        }
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(artist.name)
                                .font(Theme.sectionTitle)
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(2)
                                .accessibilityAddTraits(.isHeader)
                            if let summary {
                                TechnicalLabel(text: summary)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(
                        top: 8,
                        leading: Theme.screenPadding,
                        bottom: 12,
                        trailing: Theme.screenPadding
                    ))
                    .listRowBackground(Color.clear)

                    Button {
                        radio.start(.artist(artist.name))
                    } label: {
                        Label("Start radio", systemImage: "dot.radiowaves.left.and.right")
                            .font(Theme.listRowTitle)
                    }
                    .glassControlStyle()
                    .accessibilityHint("Plays a station built from this artist")
                }

                if let detail {
                    if let biography = detail.biography {
                        ArtistBioSection(
                            biography: biography,
                            externalLink: detail.externalLink,
                            socialLinks: detail.socialLinks
                        )
                    }
                    if !detail.topTracks.isEmpty {
                        Section {
                            ForEach(detail.topTracks) { track in
                                Button {
                                    Task { await model.play(track, in: detail.topTracks) }
                                } label: {
                                    TrackRow(
                                        track: track,
                                        isCurrent: model.player.currentTrack?.id == track.id
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            TechnicalSectionHeader(
                                title: "Top Tracks",
                                meta: "\(detail.topTracks.count) TRACKS"
                            )
                        }
                    }
                    if !detail.releases.isEmpty {
                        Section {
                            ForEach(detail.releases) { release in
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
                                            cornerRadius: Theme.tileRadius
                                        )
                                        .frame(width: 48, height: 48)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(release.title)
                                                .font(Theme.rowTitle)
                                                .foregroundStyle(Theme.primaryText)
                                                .lineLimit(1)
                                            Text(release.artist)
                                                .font(Theme.rowSubtitle)
                                                .foregroundStyle(Theme.secondaryText)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(Theme.caption)
                                            .foregroundStyle(Theme.tertiaryText)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            TechnicalSectionHeader(
                                title: "Albums",
                                meta: "\(detail.releases.count) RELEASES"
                            )
                        }
                    }
                }
            }
            .listStyle(.plain)
            .listRowSeparatorTint(Theme.separator)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .overlay { stateOverlay }
            .navigationTitle(artist.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.primaryText)
                }
            }
            .task { await load() }
            .sheet(item: $selectedRelease) { release in
                ReleaseDetailView(model: model, release: release)
            }
        }
    }

    /// What the loaded catalog knows about the artist.
    private var summary: String? {
        guard let detail else { return nil }
        var parts: [String] = []
        if !detail.topTracks.isEmpty {
            let count = detail.topTracks.count
            parts.append(count == 1 ? "1 TOP TRACK" : "\(count) TOP TRACKS")
        }
        if !detail.releases.isEmpty {
            let count = detail.releases.count
            parts.append(count == 1 ? "1 RELEASE" : "\(count) RELEASES")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if isLoading, detail == nil {
            ProgressView("Loading artist…")
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Artist unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Retry") { Task { await load() } }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await model.artistDetail(id: artist.id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
#endif
