// QueueView.swift: inspect, jump around, reorder and remove queued tracks.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct QueueView: View {
    let player: PlayerController
    @Environment(\.dismiss) private var dismiss

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
                                row(track, isCurrent: index == player.queue.currentIndex)
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

    private func row(_ track: Track, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            if isCurrent {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                Text(track.displayArtist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays this queued track")
    }
}
#endif
