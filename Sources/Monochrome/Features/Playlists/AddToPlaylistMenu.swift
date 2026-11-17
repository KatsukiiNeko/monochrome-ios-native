// AddToPlaylistMenu.swift: the shared "add to playlist" action for any track.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

/// A submenu that works inside a context menu or another menu. A playlist that
/// already holds the track shows an explicit "Add anyway" action, so a duplicate
/// is only ever created by choice.
struct AddToPlaylistMenu: View {
    let track: Track

    @Environment(PlaylistModel.self) private var playlists

    var body: some View {
        Menu {
            if playlists.playlists.isEmpty {
                Text("Create a playlist in Library first")
            } else {
                ForEach(playlists.playlists) { playlist in
                    Button(title(for: playlist)) {
                        playlists.add(
                            track,
                            to: playlist.id,
                            allowDuplicate: playlist.contains(track)
                        )
                    }
                    .disabled(playlist.items.count >= PlaylistCollection.maxTracksPerPlaylist)
                }
            }
        } label: {
            Label("Add to playlist", systemImage: "text.badge.plus")
        }
        .accessibilityLabel("Add to playlist")
    }

    private func title(for playlist: Playlist) -> String {
        guard playlist.contains(track) else { return playlist.name }
        return "Add anyway to \(playlist.name)"
    }
}
#endif
