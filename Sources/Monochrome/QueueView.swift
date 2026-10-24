// QueueView.swift: current track and upcoming queue with jump, reorder and remove.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct QueueView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accentColor) private var accent

    private var player: PlayerController { model.player }

    private struct Entry: Identifiable {
        let index: Int
        let track: Track
        var id: Int { index }
    }

    private var upcoming: [Entry] {
        guard let current = player.queue.currentIndex else { return [] }
        let start = current + 1
        guard start < player.queue.tracks.count else { return [] }
        return (start..<player.queue.tracks.count).map { index in
            Entry(index: index, track: player.queue.tracks[index])
        }
    }

    private var upcomingStart: Int {
        (player.queue.currentIndex ?? 0) + 1
    }

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
                        if let current = player.queue.current {
                            Section {
                                TrackRow(
                                    track: current,
                                    localArtworkURL: model.artworkURL(for: current),
                                    isCurrent: true
                                )
                            } header: {
                                TechnicalSectionHeader(title: "Now Playing")
                            }
                        }

                        Section {
                            if upcoming.isEmpty {
                                Text("Nothing else is queued.")
                                    .font(Theme.rowSubtitle)
                                    .foregroundStyle(Theme.secondaryText)
                            } else {
                                ForEach(upcoming) { entry in
                                    Button {
                                        Task { await player.jump(to: entry.index) }
                                    } label: {
                                        TrackRow(
                                            track: entry.track,
                                            localArtworkURL: model.artworkURL(for: entry.track)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions {
                                        Button("Remove", role: .destructive) {
                                            Task { await player.removeTrack(at: entry.index) }
                                        }
                                    }
                                }
                                .onMove { offsets, destination in
                                    guard let source = offsets.first else { return }
                                    player.moveQueue(
                                        from: source + upcomingStart,
                                        to: destination + upcomingStart
                                    )
                                }
                            }
                        } header: {
                            TechnicalSectionHeader(title: "Next in Queue")
                        }
                    }
                    .listStyle(.plain)
                    .listRowSeparatorTint(Theme.separator)
                    .scrollContentBackground(.hidden)
                    .tint(accent)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !upcoming.isEmpty {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.primaryText)
                }
            }
            .preferredColorScheme(model.appearanceMode.colorScheme)
        }
    }

}
#endif
