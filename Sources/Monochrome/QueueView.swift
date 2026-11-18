// QueueView.swift: current track and upcoming queue with jump, reorder and remove.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct QueueView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accentColor) private var accent
    @Environment(RadioModel.self) private var radio
    @State private var isConfirmingClear = false

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
                                    .contextMenu {
                                        Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                                            player.playNext(entry.track)
                                        }
                                        AddToPlaylistMenu(track: entry.track)
                                        RecommendationMenu(track: entry.track)
                                        RadioMenu(track: entry.track)
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
                            TechnicalSectionHeader(
                                title: "Next in Queue",
                                meta: radio.isRunning ? "RADIO" : nil
                            )
                        }
                    }
                    .listStyle(.plain)
                    .listRowSeparatorTint(Theme.separator)
                    .scrollContentBackground(.hidden)
        .contentMargins(.bottom, Theme.scrollBottomPadding, for: .scrollContent)
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
                    Menu {
                        if radio.isRunning {
                            Button("Stop radio", systemImage: "dot.radiowaves.left.and.right.slash") {
                                radio.stop()
                            }
                        }
                        Button("Clear queue", systemImage: "trash", role: .destructive) {
                            isConfirmingClear = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Theme.primaryText)
                    }
                    .accessibilityLabel("Queue actions")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.primaryText)
                }
            }
            .confirmationDialog(
                "Clear the queue?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button("Clear queue", role: .destructive) {
                    player.clearQueue()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Playback stops and every queued song is removed.")
            }
            .preferredColorScheme(model.appearanceMode.colorScheme)
        }
    }

}
#endif
