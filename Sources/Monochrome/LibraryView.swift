// LibraryView.swift: library filters, sort, pinned favorites and imported files.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    let model: AppModel
    var onOpenSettings: () -> Void

    @State private var filter: LibraryFilter = .all
    @State private var sort: LibrarySort = .recent
    @State private var isShowingImporter = false
    @State private var pendingDeletion: Track?

    private var rows: [Track] {
        LibraryQuery.rows(
            tracks: model.tracks,
            favorites: model.favorites,
            filter: filter,
            sort: sort
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterChips
                favoritesPinnedRow
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.bottom, 8)

                List {
                    ForEach(rows) { track in
                        Button {
                            Task { await model.play(track, in: rows) }
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
                            if track.provider == Track.localProvider {
                                Button("Delete", role: .destructive) {
                                    pendingDeletion = track
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .listRowSeparatorTint(Theme.separator)
                .scrollContentBackground(.hidden)
                .overlay {
                    if model.isImporting {
                        ProgressView("Importing…")
                            .padding()
                            .glassSurface(cornerRadius: Theme.cardRadius)
                    } else if rows.isEmpty {
                        emptyState
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    sortMenu
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Import audio files", systemImage: "plus") {
                        isShowingImporter = true
                    }
                    .foregroundStyle(Theme.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { onOpenSettings() }
                        .foregroundStyle(Theme.primaryText)
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

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases) { option in
                    Chip(title: option.title, isSelected: filter == option) {
                        filter = option
                    }
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 8)
        }
    }

    private var favoritesPinnedRow: some View {
        Button {
            filter = .favorites
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 48, height: 48)
                    .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.tileRadius))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Favorites")
                        .font(Theme.rowTitle)
                        .foregroundStyle(Theme.primaryText)
                    TechnicalLabel(
                        text: model.favorites.count == 1 ? "1 song" : "\(model.favorites.count) songs"
                    )
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: Theme.hairline)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Favorites, \(model.favorites.count) songs")
        .accessibilityHint("Shows favorite tracks")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(LibrarySort.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(Theme.primaryText)
        }
        .accessibilityLabel("Sort library")
        .accessibilityValue(sort.title)
    }

    @ViewBuilder
    private var emptyState: some View {
        switch filter {
        case .all:
            ContentUnavailableView {
                Label("No music yet", systemImage: "music.note.list")
            } description: {
                Text("Import audio files from the Files app, or search the catalog.")
            } actions: {
                Button("Import audio files") { isShowingImporter = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primaryAction)
            }
        case .favorites:
            ContentUnavailableView {
                Label("No favorites yet", systemImage: "heart")
            } description: {
                Text("Tap the heart in the player, or swipe a track to the right.")
            }
        case .local:
            ContentUnavailableView {
                Label("No local files", systemImage: "folder")
            } description: {
                Text("Import audio files from the Files app.")
            } actions: {
                Button("Import audio files") { isShowingImporter = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primaryAction)
            }
        }
    }
}
#endif
