// NextTrackPreparation.swift: when it is worth staging the next track.
import Foundation

public enum NextTrackPreparation {
    /// Pure decision so the rules can be tested without a network monitor.
    public static func shouldPrepare(
        currentPosition: Double,
        duration: Double,
        hasNextTrack: Bool,
        isPreparing: Bool,
        isUnmeteredWiFi: Bool,
        isInBackground: Bool,
        nextIsNetwork: Bool
    ) -> Bool {
        guard !isInBackground else { return false }
        guard isUnmeteredWiFi else { return false }
        guard hasNextTrack, nextIsNetwork else { return false }
        guard !isPreparing else { return false }
        guard duration > 0 else { return false }
        return currentPosition / duration >= 0.5
    }
}