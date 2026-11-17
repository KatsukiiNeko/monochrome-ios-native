// RecommendationMenu.swift: the feedback actions for a track.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

/// "More like this" and "Not for me" for a track row. The actions stay away
/// while the shelf is switched off.
struct RecommendationMenu: View {
    let track: Track

    @Environment(RecommendationModel.self) private var recommendations

    var body: some View {
        if recommendations.isEnabled {
            Button("More like this", systemImage: "sparkles") {
                recommendations.moreLikeThis(track)
            }
            Button("Not for me", systemImage: "hand.thumbsdown") {
                recommendations.notForMe(track)
            }
        }
    }
}
#endif
