// TrackURLResolver.swift: turns a track into a playable URL at play time.
import Foundation

public protocol TrackURLResolver: Sendable {
    func url(for track: Track) async throws -> URL
}

public enum TrackResolutionError: LocalizedError, Equatable {
    case missingFile(String)
    case notStreamable(String)

    public var errorDescription: String? {
        switch self {
        case .missingFile(let title):
            "The audio file for “\(title)” is missing."
        case .notStreamable(let title):
            "“\(title)” cannot be streamed. Check the streaming host in Settings, then retry."
        }
    }
}

/// Actor because the streaming client is replaced when the host setting changes,
/// while the player keeps one resolver for its whole lifetime.
public actor DefaultTrackResolver: TrackURLResolver {
    public let localDirectory: URL
    private var client: TracksAPIClient?

    public init(localDirectory: URL, client: TracksAPIClient? = nil) {
        self.localDirectory = localDirectory
        self.client = client
    }

    /// `nil` means streaming is switched off; local playback keeps working.
    public func useStreamingClient(_ client: TracksAPIClient?) {
        self.client = client
    }

    public func url(for track: Track) async throws -> URL {
        if track.isStreaming {
            guard let client, let streamURL = await client.streamURL(for: track) else {
                throw TrackResolutionError.notStreamable(track.title)
            }
            return streamURL
        }
        guard !track.fileName.isEmpty else {
            throw TrackResolutionError.missingFile(track.title)
        }
        let url = localDirectory.appendingPathComponent(track.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TrackResolutionError.missingFile(track.title)
        }
        return url
    }
}
