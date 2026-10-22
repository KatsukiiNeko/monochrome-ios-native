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
                    HStack(spacing: 16) {
                        TrackArtwork(
                            track: Track(
                                title: release.title,
                                artist: release.artist,
                                artworkURL: release.artworkURL
                            ),
                            cornerRadius: 10
                        )
                        .frame(width: 96, height: 96)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(release.title)
                                .font(.headline)
                            Text(release.artist)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let count = release.trackCount {
                                Text("\(count) tracks")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
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
                }
            }
            .listStyle(.plain)
            .overlay { stateOverlay }
            .navigationTitle(release.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
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
    @State private var detail: RemoteArtistDetail?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var selectedRelease: RemoteRelease?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        AsyncImage(url: artist.avatarURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Circle().fill(Color(white: 0.14))
                            }
                        }
                        .frame(width: 88, height: 88)
                        .clipShape(Circle())

                        Text(artist.name)
                            .font(.title3.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }

                if let detail {
                    if !detail.topTracks.isEmpty {
                        Section("Top tracks") {
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
                        }
                    }
                    if !detail.releases.isEmpty {
                        Section("Albums") {
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
                                            cornerRadius: 6
                                        )
                                        .frame(width: 48, height: 48)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(release.title).font(.subheadline)
                                            Text(release.artist)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay { stateOverlay }
            .navigationTitle(artist.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .sheet(item: $selectedRelease) { release in
                ReleaseDetailView(model: model, release: release)
            }
        }
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
