// RadioMenu.swift: the "Start radio" action for a track.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct RadioMenu: View {
    let track: Track

    @Environment(RadioModel.self) private var radio

    var body: some View {
        Button("Start radio", systemImage: "dot.radiowaves.left.and.right") {
            radio.start(.track(track))
        }
    }
}
#endif
