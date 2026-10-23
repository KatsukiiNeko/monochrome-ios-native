// DownloadsView.swift: permanent offline files, separate from the temporary cache.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct DownloadsView: View {
    let model: AppModel

    @State private var pendingRemoval: DownloadItem?

    private var tracks: [Track] { model.completedDownloads.map(\.track) }

    var body: some View {
        List {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    Task { await model.player.play(tracks: tracks, startingAt: index) }
                } label: {
                    TrackRow(
                        track: track,
                        isCurrent: model.player.currentTrack?.id == track.id,
                        showsDuration: true
                    )
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Remove", role: .destructive) {
                        pendingRemoval = model.completedDownloads.first { $0.track.id == track.id }
                    }
                }
            }
        }
        .listStyle(.plain)
        .listRowSeparatorTint(Theme.separator)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if tracks.isEmpty {
                ContentUnavailableView {
                    Label("No downloads", systemImage: "arrow.down.circle")
                } description: {
                    Text("Download a song from its menu to keep it available offline.")
                }
            }
        }
        .task { await model.refreshDownloads() }
        .confirmationDialog(
            "Remove “\(pendingRemoval?.track.title ?? "this download")”?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove download", role: .destructive) {
                guard let item = pendingRemoval else { return }
                pendingRemoval = nil
                Task { await model.removeDownload(item) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("The offline copy is deleted. You can download it again later.")
        }
    }
}
#endif
