// SearchView.swift: debounced catalog search whose results play through the shared player.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct SearchView: View {
    let model: AppModel

    @State private var query = ""
    @State private var results: [Track] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        List(results) { track in
            Button {
                Task { await model.play(track, in: results) }
            } label: {
                RemoteTrackRow(
                    track: track,
                    isCurrent: model.player.currentTrack?.id == track.id
                )
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
        .overlay { stateOverlay }
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Tracks, artists, albums"
        )
        .task(id: query) { await runSearch() }
        .navigationTitle("Search")
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if !model.isStreamingConfigured {
            ContentUnavailableView {
                Label("Streaming is off", systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
                Text("Choose a streaming host in Settings to search the catalog.")
            }
        } else if isSearching {
            ProgressView("Searching…")
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Search failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Retry") { Task { await runSearch(force: true) } }
            }
        } else if trimmedQuery.isEmpty {
            ContentUnavailableView {
                Label("Search the catalog", systemImage: "magnifyingglass")
            } description: {
                Text("Find tracks by name or artist.")
            }
        } else if results.isEmpty {
            ContentUnavailableView.search(text: trimmedQuery)
        }
    }

    private func runSearch(force: Bool = false) async {
        let text = trimmedQuery
        guard text.count >= 2 else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }
        if !force {
            // Debounce. SwiftUI cancels this task when the query changes again,
            // and the cancellation checks below drop the stale response.
            try? await Task.sleep(for: .milliseconds(300))
        }
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await model.searchTracks(text)
            guard !Task.isCancelled else { return }
            results = found
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            errorMessage = error.localizedDescription
        }
    }
}

/// Catalog row: remote artwork, title, artist and duration.
struct RemoteTrackRow: View {
    let track: Track
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: track.artworkURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "music.note")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                Text(track.displayArtist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let duration = track.durationSeconds {
                Text(formatDuration(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays this track")
    }
}
#endif
