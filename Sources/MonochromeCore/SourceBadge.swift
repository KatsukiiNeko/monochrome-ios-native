// SourceBadge.swift: one short label for a source and its quality.
import Foundation

public enum SourceBadge {
    public static func text(providerID: String, quality: AudioQuality?) -> String {
        let name: String
        switch providerID {
        case MusicSourceID.monochrome.rawValue: name = "HiFi"
        case MusicSourceID.youTubeMusic.rawValue: name = "YT Music"
        case MusicSourceID.podcast.rawValue: name = "Podcast"
        case Track.localProvider: name = "Local"
        default: name = providerID
        }
        if let quality {
            return "\(name) · \(quality.rawValue.capitalized)"
        }
        return name
    }
}