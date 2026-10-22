// ContentView.swift: the library list, import entry point and mini player host.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = AppModel()
    @State private var isShowingImporter = false
    @State private var isShowingPlayer = false
    @State private var pendingDeletion: Track?

    var body: some View {
        NavigationStack {
            Group {
                if model.tracks.isEmpty {
                    emptyState
                } else {
                    libraryList
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Import audio files", systemImage: "plus") {
                        isShowingImporter = true
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if model.player.currentTrack != nil {
                    MiniPlayerView(player: model.player) { isShowingPlayer = true }
                }
            }
            .sheet(isPresented: $isShowingPlayer) {
                PlayerView(player: model.player)
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
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.clearError() } }
                )
            ) {
                Button("OK", role: .cancel) { model.clearError() }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .task { await model.loadTracks() }
    }

    private var libraryList: some View {
        List(model.tracks) { track in
            Button {
                Task { await model.play(track) }
            } label: {
                TrackRow(track: track, isCurrent: model.player.currentTrack?.id == track.id)
            }
            .buttonStyle(.plain)
            .swipeActions {
                Button("Delete", role: .destructive) {
                    pendingDeletion = track
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if model.isImporting {
                ProgressView("Importing…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No music yet", systemImage: "music.note.list")
        } description: {
            Text("Import audio files from the Files app to start listening.")
        } actions: {
            Button("Import audio files") { isShowingImporter = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct TrackRow: View {
    let track: Track
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.headline)
                Text(track.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let duration = track.durationSeconds {
                Text(formatDuration(duration))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays this track")
    }
}
#endif
