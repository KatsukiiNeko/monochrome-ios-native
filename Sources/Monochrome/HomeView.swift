// HomeView.swift: greeting, recently played and favorites, all from persisted data.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct HomeView: View {
    let model: AppModel
    var onOpenPlayer: () -> Void
    var onOpenSearch: () -> Void
    var onOpenLibrary: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    greeting

                    if !model.recents.isEmpty {
                        recentsSection
                    }
                    if !model.favorites.isEmpty {
                        favoritesSection
                    }
                    if model.recents.isEmpty && model.favorites.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 24)
            }
            .background(Color(white: 0.05).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { logo }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { onOpenSettings() }
                }
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.greeting(for: .now))
                .font(.largeTitle.bold())
            Text("Pick up where you left off.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    /// The web app's own logo, unchanged; hidden if the resource is not bundled.
    @ViewBuilder
    private var logo: some View {
        if let image = UIImage(named: "monochrome_logo") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(height: 18)
                .accessibilityLabel("Monochrome")
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recently played")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.recents) { track in
                        Button {
                            Task { await model.play(track, in: model.recents) }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                TrackArtwork(
                                    track: track,
                                    localURL: model.artworkURL(for: track),
                                    cornerRadius: 10
                                )
                                .frame(width: 132, height: 132)
                                Text(track.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text(track.displayArtist)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 132, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(track.title) by \(track.displayArtist)")
                        .accessibilityHint("Plays this track")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("Favorites")
                Spacer()
                Button("See all") { onOpenLibrary() }
                    .font(.caption)
            }
            VStack(spacing: 0) {
                ForEach(model.favorites.prefix(5)) { track in
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
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing here yet", systemImage: "sparkles")
        } description: {
            Text("Search the catalog to start listening, or import files in the Library.")
        } actions: {
            Button("Search the catalog") { onOpenSearch() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, 40)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
    }

    private static func greeting(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}
#endif
