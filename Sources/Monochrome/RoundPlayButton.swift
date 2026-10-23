// RoundPlayButton.swift: the large white play/pause control.
#if canImport(SwiftUI)
import SwiftUI

struct RoundPlayButton: View {
    let isPlaying: Bool
    var isLoading = false
    var size: CGFloat = 64
    var action: () -> Void

    var body: some View {
        if isLoading {
            ProgressView()
                .controlSize(.large)
                .frame(width: size, height: size)
                .accessibilityLabel("Loading")
        } else {
            Button(action: action) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(Theme.background)
                    .frame(width: size, height: size)
                    .background(Theme.accent, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")
        }
    }
}
#endif
