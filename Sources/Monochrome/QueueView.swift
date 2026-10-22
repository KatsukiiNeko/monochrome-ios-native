// QueueView.swift: inspect, jump around, reorder and remove queued tracks.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct QueueView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss

    private var player: PlayerController { model.player }

    var body: some View {
        NavigationStack {
            Group {
                if player.queue.isEmpty {
                    ContentUnavailableView(
                        "Queue is empty",
                        systemImage: "list.bullet",
                        description: Text("Play a track from the library to fill it.")
                    )
                } else {
                    List {
                        ForEach(Array(player.queue.tracks.enumerated()), id: \.element.id) { index, track in
                            Button {
                                Task { await player.jump(to: index) }
                            } label: {
                                TrackRow(
                                    track: track,
                                    localArtworkURL: model.artworkURL(for: track),
                                    isCurrent: index == player.queue.currentIndex
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    Task { await player.removeTrack(at: index) }
                                }
                            }
                        }
                        .onMove { offsets, destination in
                            guard let source = offsets.first else { return }
                            player.moveQueue(from: source, to: destination)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
#endif
