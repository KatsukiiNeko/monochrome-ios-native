// NowPlayingBar.swift: presentation values for the persistent now-playing bar.
import Foundation

/// Derived from the shared player state; the bar renders these values and owns no state.
public struct NowPlayingBar: Equatable, Sendable {
    public var title: String
    public var subtitle: String
    public var badgeText: String?
    public var badgeSpokenText: String?
    /// Clamped to 0...1; zero when the duration is still unknown.
    public var progress: Double
    public var isPlaying: Bool
    public var isLoading: Bool
    public var failureMessage: String?

    public init(
        title: String,
        subtitle: String,
        badgeText: String? = nil,
        badgeSpokenText: String? = nil,
        progress: Double = 0,
        isPlaying: Bool = false,
        isLoading: Bool = false,
        failureMessage: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badgeText = badgeText
        self.badgeSpokenText = badgeSpokenText
        self.progress = progress
        self.isPlaying = isPlaying
        self.isLoading = isLoading
        self.failureMessage = failureMessage
    }

    /// `nil` means nothing is loaded, which is the only case where the bar hides.
    public static func make(
        track: Track?,
        state: PlaybackState,
        position: Double,
        duration: Double,
        format: AudioFormat? = nil
    ) -> NowPlayingBar? {
        guard let track else { return nil }
        let total = duration > 0 ? duration : (track.durationSeconds ?? 0)
        let fraction = total > 0 ? min(max(position / total, 0), 1) : 0
        var failure: String?
        if case .failed(let message) = state { failure = message }
        return NowPlayingBar(
            title: track.title,
            subtitle: track.displayArtist,
            badgeText: AudioBadge.text(format: format, quality: track.audioQuality),
            badgeSpokenText: AudioBadge.accessibilityLabel(format: format, quality: track.audioQuality),
            progress: fraction,
            isPlaying: state == .playing,
            isLoading: state == .loading,
            failureMessage: failure
        )
    }
}
