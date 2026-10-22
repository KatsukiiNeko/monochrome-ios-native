// LibraryView.swift: imported files and favorites, with import and delete.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    let model: AppModel
    var onOpenPlayer: () -> Void
    var onOpenSettings: () -> Void

    @State private var scope: Scope = .imported
    @State private var isShowingImporter = false
    @State private var pendingDeletion: Track?

    private enum Scope: String, CaseIterable, Identifiable {
        case imported = "Imported"
        case favorites = "Favorites"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Source", selection: $scope) {
                    ForEach(Scope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 8)

                content
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Import audio files", systemImage: "plus") {
                        isShowingImporter = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { onOpenSettings() }
                }
            }
            .fileImporter(
                isPresented: $isShowingImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await model.importFiles(urls) }
                case .failure(let error):
                    model.report(error)
                }
            }
            .confirmationDialog(
                "Delete “\(pendingDeletion?.title ?? "this track")”?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let track = pendingDeletion else { return }
                    pendingDeletion = nil
                    Task { await model.delete(track) }
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("This removes the app's copy. The original file in Files is untouched.")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch scope {
        case .imported: importedList
        case .favorites: favoritesList
        }
    }

    private var importedList: some View {
        List {
            ForEach(model.tracks) { track in
                Button {
                    Task { await model.play(track, in: model.tracks) }
                } label: {
                    TrackRow(
                        track: track,
                        localArtworkURL: model.artworkURL(for: track),
                        isCurrent: model.player.currentTrack?.id == track.id,
                        showsFavorite: true,
                        isFavorite: model.isFavorite(track)
                    )
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading) {
                    Button(
                        model.isFavorite(track) ? "Unfavorite" : "Favorite",
                        systemImage: model.isFavorite(track) ? "heart.slash" : "heart"
                    ) {
                        model.toggleFavorite(track)
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        pendingDeletion = track
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if model.isImporting {
                ProgressView("Importing…")
                    .padding()
                    .glassSurface(cornerRadius: 12)
            } else if model.tracks.isEmpty {
                ContentUnavailableView {
                    Label("No music yet", systemImage: "music.note.list")
                } description: {
                    Text("Import audio files from the Files app, or search the catalog.")
                } actions: {
                    Button("Import audio files") { isShowingImporter = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var favoritesList: some View {
        List {
            ForEach(model.favorites) { track in
                Button {
                    Task { await model.play(track, in: model.favorites) }
                } label: {
                    TrackRow(
                        track: track,
                        localArtworkURL: model.artworkURL(for: track),
                        isCurrent: model.player.currentTrack?.id == track.id,
                        showsFavorite: true,
                        isFavorite: true
                    )
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Unfavorite", systemImage: "heart.slash", role: .destructive) {
                        model.toggleFavorite(track)
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if model.favorites.isEmpty {
                ContentUnavailableView {
                    Label("No favorites yet", systemImage: "heart")
                } description: {
                    Text("Tap the heart in the player, or swipe a track to the right.")
                }
            }
        }
    }
}
#endif
