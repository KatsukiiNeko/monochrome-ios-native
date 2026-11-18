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
    @Environment(\.accentColor) private var accent
    @Environment(RecommendationModel.self) private var recommendations
    @Environment(RadioModel.self) private var radio

    private var quickAccess: [Track] {
        QuickAccess.merge(recents: model.recents, favorites: model.favorites)
    }

    private var hasContent: Bool {
        !model.recents.isEmpty || !model.favorites.isEmpty || !model.completedDownloads.isEmpty
    }

    private var stationArtists: [String] {
        HomeStations.artists(favorites: model.favorites, recents: model.recents)
    }

    private var recentDownloads: [DownloadItem] {
        Array(model.completedDownloads.prefix(6))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    greeting

                    if !quickAccess.isEmpty {
                        quickAccessGrid
                    }
                    RecommendationShelf(model: model)
                    if !model.recents.isEmpty {
                        listenAgainSection
                    }
                    if !recentDownloads.isEmpty {
                        recentlyDownloadedSection
                    }
                    if !stationArtists.isEmpty {
                        stationsSection
                    }
                    if !model.favorites.isEmpty {
                        favoritesSection
                    }
                    if !hasContent {
                        emptyState
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, Theme.scrollBottomPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .refreshable {
                if recommendations.isEnabled { await recommendations.refreshIfNeeded() }
                await model.refreshDownloads()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { logo }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { onOpenSettings() }
                        .foregroundStyle(Theme.primaryText)
                }
            }
            .task {
                await recommendations.refreshIfNeeded()
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(accent)
                    .frame(width: 4, height: 4)
                    .accessibilityHidden(true)
                DotMatrixLabel(
                    text: "Monochrome",
                    color: Theme.primaryText,
                    dotSize: 2.0
                )
            }
            Text(Self.greeting(for: .now))
                .font(Theme.screenTitle)
                .foregroundStyle(Theme.primaryText)
            Text("Pick up where you left off.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Rectangle()
                .fill(Theme.separator)
                .frame(height: Theme.hairline)
                .padding(.top, 10)
                .accessibilityHidden(true)
        }
        .padding(.top, 8)
    }

    /// The web app's own logo, unchanged; hidden if the resource is not bundled.
    @ViewBuilder
    private var logo: some View {
        if let image = UIImage(named: "monochrome_logo") {
            Image(uiImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Theme.primaryText)
                .frame(height: 18)
                .accessibilityLabel("Monochrome")
        }
    }

    private var quickAccessGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShelfHeader(
                title: "Quick access",
                meta: quickAccess.count == 1 ? "1 TRACK" : "\(quickAccess.count) TRACKS"
            )

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
                                    .fill(accent)
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
            ShelfHeader(
                title: "Listen again",
                meta: min(model.recents.count, 10) == 1 ? "1 TRACK" : "\(min(model.recents.count, 10)) TRACKS"
            )
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

    private var recentlyDownloadedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShelfHeader(
                title: "Recently downloaded",
                meta: recentDownloads.count == 1 ? "1 SONG" : "\(recentDownloads.count) SONGS",
                actionTitle: "Manage"
            ) {
                onOpenLibrary()
            }
            VStack(spacing: 0) {
                ForEach(Array(recentDownloads.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: Theme.hairline)
                            .padding(.leading, 64)
                            .accessibilityHidden(true)
                    }
                    Button {
                        Task { await model.play(item.track, in: recentDownloads.map(\.track)) }
                    } label: {
                        TrackRow(
                            track: item.track,
                            localArtworkURL: model.artworkURL(for: item.track),
                            isCurrent: model.player.currentTrack?.id == item.track.id
                        )
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Plays this track")
                }
            }
        }
    }

    private var stationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShelfHeader(
                title: "Stations",
                meta: "FROM YOUR ARTISTS"
            )
            VStack(spacing: 0) {
                ForEach(Array(stationArtists.enumerated()), id: \.element) { index, artist in
                    if index > 0 {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: Theme.hairline)
                            .padding(.leading, 48)
                            .accessibilityHidden(true)
                    }
                    Button {
                        radio.start(.artist(artist))
                    } label: {
                        HStack(spacing: Theme.rowSpacing) {
                            TechnicalIcon(name: "dot.radiowaves.left.and.right")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(artist)
                                    .font(Theme.listRowTitle)
                                    .foregroundStyle(Theme.primaryText)
                                    .lineLimit(1)
                                TechnicalLabel(text: "Radio")
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "play.fill")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.tertiaryText)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: Theme.rowMinHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start a radio from \(artist)")
                }
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
