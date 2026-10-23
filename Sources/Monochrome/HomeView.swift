// HomeView.swift: greeting, quick access, recently played and favorites.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct HomeView: View {
    let model: AppModel
    var onOpenSearch: () -> Void
    var onOpenLibrary: () -> Void
    var onOpenSettings: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var quickAccess: [Track] {
        QuickAccess.merge(recents: model.recents, favorites: model.favorites)
    }

    private var hasContent: Bool {
        !model.recents.isEmpty || !model.favorites.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    greeting

                    if !quickAccess.isEmpty {
                        quickAccessGrid
                    }
                    if !model.recents.isEmpty {
                        listenAgainSection
                    }
                    if !model.favorites.isEmpty {
                        favoritesSection
                    }
                    if !hasContent {
                        emptyState
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .tint(Theme.accent)
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
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
                TechnicalLabel(text: "Monochrome")
            }
            Text(Self.greeting(for: .now))
                .font(Theme.screenTitle)
                .foregroundStyle(Theme.primaryText)
            Text("Pick up where you left off.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
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

    private var quickAccessGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShelfHeader(title: "Quick access")

            LazyVGrid(columns: gridColumns, spacing: 8) {
                ForEach(quickAccess) { track in
                    Button {
                        Task { await model.play(track, in: quickAccess) }
                    } label: {
                        HStack(spacing: 8) {
                            TrackArtwork(
                                track: track,
                                localURL: model.artworkURL(for: track),
                                cornerRadius: Theme.tileRadius
                            )
                            .frame(width: 48, height: 48)

                            Text(track.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if model.player.currentTrack?.id == track.id {
                                Rectangle()
                                    .fill(Theme.accent)
                                    .frame(width: 5, height: 5)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(6)
                        .background(
                            Theme.surface,
                            in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                                .stroke(Theme.border, lineWidth: Theme.hairline)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        model.player.currentTrack?.id == track.id
                            ? "\(track.title) by \(track.displayArtist), now playing"
                            : "\(track.title) by \(track.displayArtist)"
                    )
                    .accessibilityHint("Plays this track")
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]
    }

    private var listenAgainSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShelfHeader(title: "Listen again")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(model.recents.prefix(10)) { track in
                        ArtworkTile(
                            track: track,
                            localArtworkURL: model.artworkURL(for: track),
                            width: 132
                        ) {
                            Task { await model.play(track, in: model.recents) }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShelfHeader(title: "Your favorites", actionTitle: "See all") {
                onOpenLibrary()
            }
            VStack(spacing: 0) {
                ForEach(Array(model.favorites.prefix(5).enumerated()), id: \.element.id) { index, track in
                    if index > 0 {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: Theme.hairline)
                            .padding(.leading, 64)
                            .accessibilityHidden(true)
                    }
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
                .tint(Theme.primaryAction)
        }
        .padding(.top, 40)
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
