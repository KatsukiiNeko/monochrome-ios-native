// PlaylistDetailView.swift: one playlist with play, reorder and song actions.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct PlaylistDetailView: View {
    let model: AppModel
    let playlistID: String

    @Environment(PlaylistModel.self) private var playlists
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accentColor) private var accent

    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isConfirmingDelete = false
    @State private var exportURL: IdentifiableURL?

    private var playlist: Playlist? { playlists.playlist(id: playlistID) }

    var body: some View {
        Group {
            if let playlist {
                content(playlist)
            } else {
                ContentUnavailableView {
                    Label("Playlist removed", systemImage: "music.note.list")
                } description: {
                    Text("This playlist no longer exists.")
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: Binding(get: { exportURL }, set: { exportURL = $0 })) { shared in
            ActivityShareSheet(items: [shared.url])
        }
        .alert("Rename playlist", isPresented: $isRenaming) {
            TextField("Name", text: $renameText)
            Button("Save") { playlists.rename(id: playlistID, to: renameText) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete this playlist?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                playlists.delete(id: playlistID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The songs stay in your library; only the playlist is removed.")
        }
    }

    private func content(_ playlist: Playlist) -> some View {
        List {
            Section {
                header(playlist)
                    .listRowInsets(EdgeInsets(
                        top: 8,
                        leading: Theme.screenPadding,
                        bottom: 12,
                        trailing: Theme.screenPadding
                    ))
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(Array(playlist.items.enumerated()), id: \.offset) { index, track in
                    Button {
                        Task { await model.player.play(tracks: playlist.items, startingAt: index) }
                    } label: {
                        TrackRow(
                            track: track,
                            localArtworkURL: model.artworkURL(for: track),
                            isCurrent: model.player.currentTrack?.sourceKey == track.sourceKey
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            playlists.removeItem(at: index, from: playlistID)
                        }
                    }
                    .contextMenu {
                        AddToPlaylistMenu(track: track)
                        RecommendationMenu(track: track)
                        RadioMenu(track: track)
                        Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                            model.player.playNext(track)
                        }
                        Button("Add to queue", systemImage: "text.badge.plus") {
                            model.player.append([track])
                        }
                        Divider()
                        Button("Remove from playlist", systemImage: "minus.circle", role: .destructive) {
                            playlists.removeItem(at: index, from: playlistID)
                        }
                    }
                }
                .onMove { offsets, destination in
                    guard let source = offsets.first else { return }
                    playlists.moveTrack(in: playlistID, from: source, to: destination)
                }
            } header: {
                TechnicalSectionHeader(
                    title: "Songs",
                    meta: playlist.items.isEmpty ? "EMPTY" : "\(playlist.items.count)"
                )
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.separator)
        .scrollContentBackground(.hidden)
        .overlay {
            if playlist.items.isEmpty {
                ContentUnavailableView {
                    Label("No songs yet", systemImage: "music.note")
                } description: {
                    Text("Add songs from the Library, Search or Now Playing.")
                }
            }
        }
        .tint(accent)
    }

    private func header(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(playlist.name)
                .font(Theme.heroTitle)
                .foregroundStyle(Theme.primaryText)
                .accessibilityAddTraits(.isHeader)

            TechnicalLabel(text: summary(playlist))

            HStack(spacing: 10) {
                Button {
                    Task { await model.player.play(tracks: playlist.items, startingAt: 0) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                        .font(Theme.listRowTitle)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primaryAction)
                .foregroundStyle(Theme.onPrimaryAction)
                .disabled(playlist.items.isEmpty)
                .accessibilityHint("Plays this playlist in order")

                Button {
                    Task {
                        await model.player.play(tracks: playlist.items, startingAt: 0)
                        if !model.player.isShuffled { model.player.toggleShuffle() }
                    }
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(Theme.listRowTitle)
                }
                .glassControlStyle()
                .disabled(playlist.items.isEmpty)
                .accessibilityHint("Plays this playlist in a random order")

                Button {
                    model.player.append(playlist.items)
                } label: {
                    Label("Queue", systemImage: "text.badge.plus")
                        .font(Theme.listRowTitle)
                }
                .glassControlStyle()
                .disabled(playlist.items.isEmpty)
                .accessibilityLabel("Add playlist to queue")
            }
            .padding(.top, 2)
        }
    }

    private func summary(_ playlist: Playlist) -> String {
        let songs = playlist.items.count == 1 ? "1 SONG" : "\(playlist.items.count) SONGS"
        guard playlist.totalDuration > 0 else { return songs }
        return "\(songs) · \(formatDuration(playlist.totalDuration))"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let playlist, playlist.items.count > 1 {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
                    .foregroundStyle(Theme.primaryText)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Rename", systemImage: "pencil") {
                    renameText = playlist?.name ?? ""
                    isRenaming = true
                }
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    playlists.duplicate(id: playlistID)
                }
                if let playlist, !playlist.items.isEmpty {
                    Divider()
                    Button("Export as JSON", systemImage: "curlybraces") {
                        export(asJSON: true, playlist: playlist)
                    }
                    Button("Export as CSV", systemImage: "tablecells") {
                        export(asJSON: false, playlist: playlist)
                    }
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Theme.primaryText)
            }
            .accessibilityLabel("Playlist actions")
        }
    }

    /// Writes the playlist to a file and hands it to the system share sheet.
    private func export(asJSON: Bool, playlist: Playlist) {
        let url: URL?
        if asJSON {
            url = try? PlaylistExport.writeJSON(name: playlist.name, items: playlist.items)
        } else {
            url = try? PlaylistExport.writeCSV(name: playlist.name, items: playlist.items)
        }
        if let url {
            exportURL = IdentifiableURL(url: url)
        }
    }

    private struct IdentifiableURL: Identifiable {
        let id = UUID()
        let url: URL
    }
}
#endif
