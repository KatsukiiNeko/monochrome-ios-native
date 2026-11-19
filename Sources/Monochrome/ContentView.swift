// ContentView.swift: the app shell — three tabs, one mini player, one player sheet.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct ContentView: View {
    @State private var model: AppModel
    @State private var playlists: PlaylistModel
    @State private var importer: PlaylistImportModel
    @State private var recommendations: RecommendationModel
    @State private var radio: RadioModel
    @State private var podcasts: PodcastModel
    @State private var tab: AppTab = .home
    @State private var isShowingPlayer = false
    @State private var isShowingSettings = false

    init() {
        let model = AppModel.shared
        let playlists = PlaylistModel()
        _model = State(initialValue: model)
        _playlists = State(initialValue: playlists)
        // The importer asks the catalog through the app model; it keeps no
        // catalog state of its own.
        _importer = State(initialValue: PlaylistImportModel(
            playlists: playlists,
            search: { try await model.searchTracks($0) }
        ))
        // The recommendations use the same catalog and the player's own log.
        _recommendations = State(initialValue: RecommendationModel(
            player: model.player,
            search: { try await model.searchTracks($0) },
            library: { model.recents + model.favorites }
        ))
        // The radio asks the same catalog and avoids the recent plays.
        _radio = State(initialValue: RadioModel(
            player: model.player,
            search: { try await model.searchTracks($0) },
            recents: { model.recents }
        ))
        // Podcast episodes play through the same player.
        _podcasts = State(initialValue: PodcastModel(player: model.player))
    }

    private enum AppTab: Hashable {
        case home
        case search
        case library
    }

    var body: some View {
        TabView(selection: $tab) {
            HomeView(
                model: model,
                onOpenSearch: { tab = .search },
                onOpenLibrary: { tab = .library },
                onOpenSettings: { isShowingSettings = true }
            )
            .nowPlayingBarInset(isPresented: isPlayingBarVisible) { miniPlayer }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(AppTab.home)

            SearchView(model: model)
                .nowPlayingBarInset(isPresented: isPlayingBarVisible) { miniPlayer }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(AppTab.search)

            LibraryView(
                model: model,
                onOpenSettings: { isShowingSettings = true }
            )
            .nowPlayingBarInset(isPresented: isPlayingBarVisible) { miniPlayer }
            .tabItem { Label("Library", systemImage: "music.note.list") }
            .tag(AppTab.library)
        }
        .tint(accentColor)
        .environment(\.accentColor, accentColor)
        .environment(\.onAccentColor, onAccentColor)
        .environment(playlists)
        .environment(importer)
        .environment(recommendations)
        .environment(radio)
        .environment(podcasts)
        .sheet(isPresented: $isShowingPlayer) {
            PlayerView(model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Theme.background)
                .preferredColorScheme(model.appearanceMode.colorScheme)
                .tint(accentColor)
                .environment(\.accentColor, accentColor)
                .environment(playlists)
                .environment(importer)
                .environment(recommendations)
                .environment(radio)
                .environment(podcasts)
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                SettingsView(model: model)
            }
            .presentationBackground(Theme.background)
            .preferredColorScheme(model.appearanceMode.colorScheme)
            .tint(accentColor)
            .environment(\.accentColor, accentColor)
            .environment(playlists)
            .environment(importer)
            .environment(recommendations)
            .environment(radio)
            .environment(podcasts)
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
        .task {
            // The theme has to be live before the first render of the tabs.
            Theme.definition = model.theme
            playlists.load()
            recommendations.bootstrap(favorites: model.favorites, recents: model.recents)
            await model.loadTracks()
        }
        .onChange(of: model.player.currentTrack?.id) { _, _ in
            radio.trackChanged()
        }
        .onChange(of: model.theme) { _, updated in
            Theme.definition = updated
        }
        .onChange(of: model.favorites) { _, updated in
            recommendations.syncSignals(
                favorites: updated,
                downloads: model.completedDownloads.map(\.track)
            )
        }
        .onChange(of: model.completedDownloads.map(\.track.id)) { _, _ in
            recommendations.syncSignals(
                favorites: model.favorites,
                downloads: model.completedDownloads.map(\.track)
            )
        }
        .preferredColorScheme(model.appearanceMode.colorScheme)
    }

    private var isPlayingBarVisible: Bool { model.player.currentTrack != nil }

    private var accentColor: Color {
        Theme.accentColor(preference: model.accentPreference, artwork: model.artworkAccent)
    }

    private var onAccentColor: Color {
        Theme.onAccentColor(preference: model.accentPreference, artwork: model.artworkAccent)
    }

    private var miniPlayer: some View {
        MiniPlayerView(model: model) { isShowingPlayer = true }
    }
}
#endif
