// ContentView.swift: the app shell — three tabs, one mini player, one full-screen player.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()
    @State private var tab: Tab = .home
    @State private var isShowingPlayer = false
    @State private var isShowingSettings = false

    private enum Tab: Hashable {
        case home
        case search
        case library
    }

    var body: some View {
        TabView(selection: $tab) {
            HomeView(
                model: model,
                onOpenPlayer: { isShowingPlayer = true },
                onOpenSearch: { tab = .search },
                onOpenLibrary: { tab = .library },
                onOpenSettings: { isShowingSettings = true }
            )
            .tabItem { Label("Home", systemImage: "house") }
            .tag(Tab.home)

            SearchView(model: model)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

            LibraryView(
                model: model,
                onOpenPlayer: { isShowingPlayer = true },
                onOpenSettings: { isShowingSettings = true }
            )
            .tabItem { Label("Library", systemImage: "music.note.list") }
            .tag(Tab.library)
        }
        .miniPlayerAccessory(isPresented: model.player.currentTrack != nil) {
            MiniPlayerView(model: model) { isShowingPlayer = true }
        }
        .fullScreenCover(isPresented: $isShowingPlayer) {
            PlayerView(model: model)
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                SettingsView(model: model)
            }
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
        .task { await model.loadTracks() }
    }
}
#endif
