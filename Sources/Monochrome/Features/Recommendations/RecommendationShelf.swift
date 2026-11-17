// RecommendationShelf.swift: the For You and Rediscover shelves.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

/// The home shelves built from the listening log: new picks for the listener
/// and tracks from the own library worth hearing again.
struct RecommendationShelf: View {
    let model: AppModel

    @Environment(RecommendationModel.self) private var recommendations
    @Environment(\.accentColor) private var accent

    var body: some View {
        if recommendations.isEnabled {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if recommendations.isColdStart {
            coldStart
        } else if !recommendations.recommendations.isEmpty {
            forYouSection
            rediscoverSection
        } else {
            emptyState
        }
    }

    private var forYouSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShelfHeader(title: "For you", meta: countLabel(recommendations.recommendations.count))
            VStack(spacing: 0) {
                ForEach(
                    Array(recommendations.recommendations.prefix(10).enumerated()),
                    id: \.element.id
                ) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: Theme.hairline)
                            .padding(.leading, 64)
                            .accessibilityHidden(true)
                    }
                    Button {
                        Task {
                            await model.play(
                                item.track,
                                in: recommendations.recommendations.map(\.track)
                            )
                        }
                    } label: {
                        TrackRow(
                            track: item.track,
                            localArtworkURL: model.artworkURL(for: item.track),
                            isCurrent: model.player.currentTrack?.id == item.track.id,
                            subtitle: item.reason
                        )
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Plays this track")
                    .contextMenu {
                        RecommendationMenu(track: item.track)
                    }
                }
            }
            if recommendations.isRefreshing {
                ProgressView()
                    .tint(accent)
                    .padding(.top, 6)
                    .accessibilityLabel("Looking for new picks")
            }
            if let errorMessage = recommendations.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.destructive)
                    .padding(.top, 4)
            }
        }
    }

    private var rediscoverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShelfHeader(title: "Rediscover", meta: countLabel(recommendations.rediscover.count))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(recommendations.rediscover.prefix(10)) { item in
                        ArtworkTile(
                            track: item.track,
                            localArtworkURL: model.artworkURL(for: item.track),
                            width: 132
                        ) {
                            Task {
                                await model.play(
                                    item.track,
                                    in: recommendations.rediscover.map(\.track)
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var coldStart: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShelfHeader(title: "For you", meta: "LEARNING")
            Text("Play a few tracks and your picks will show up here.")
                .font(Theme.rowSubtitle)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShelfHeader(title: "For you", meta: "NONE")
            Text("No picks yet. Play or favourite a few tracks.")
                .font(Theme.rowSubtitle)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func countLabel(_ count: Int) -> String {
        count == 1 ? "1 TRACK" : "\(count) TRACKS"
    }
}
#endif
