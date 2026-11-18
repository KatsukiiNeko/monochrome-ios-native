// PlaybackSource.swift: what actually plays, separate from a track or candidate.
import Foundation

/// The concrete media source selected for playback. A provider URL is not a
/// recording identity; this type makes the source kind explicit so the player
/// and the audio-spec UI can make correct decisions.
public enum PlaybackSource: Sendable, Equatable {
    /// A file already on disk in the app's managed storage.
    case localFile(url: URL, providerID: String, quality: AudioQuality?)
    /// A permanent download under Application Support/Downloads.
    case download(url: URL, providerID: String, quality: AudioQuality?)
    /// A temporary cache entry under Caches/AudioCache.
    case cache(url: URL, providerID: String, quality: AudioQuality?)
    /// A finite remote stream that supports seeking when the server allows it.
    case remoteStream(url: URL, headers: [String: String], providerID: String, quality: AudioQuality?, contentType: String?)
    /// A live or chunked stream with no known duration and no seeking.
    case liveStream(url: URL, headers: [String: String], providerID: String, quality: AudioQuality?, contentType: String?)

    public var url: URL {
        switch self {
        case .localFile(let url, _, _): url
        case .download(let url, _, _): url
        case .cache(let url, _, _): url
        case .remoteStream(let url, _, _, _, _): url
        case .liveStream(let url, _, _, _, _): url
        }
    }

    public var providerID: String {
        switch self {
        case .localFile(_, let id, _): id
        case .download(_, let id, _): id
        case .cache(_, let id, _): id
        case .remoteStream(_, _, let id, _, _): id
        case .liveStream(_, _, let id, _, _): id
        }
    }

    public var quality: AudioQuality? {
        switch self {
        case .localFile(_, _, let q): q
        case .download(_, _, let q): q
        case .cache(_, _, let q): q
        case .remoteStream(_, _, _, let q, _): q
        case .liveStream(_, _, _, let q, _): q
        }
    }

    public var headers: [String: String] {
        switch self {
        case .remoteStream(_, let h, _, _, _): h
        case .liveStream(_, let h, _, _, _): h
        default: [:]
        }
    }

    public var contentType: String? {
        switch self {
        case .remoteStream(_, _, _, _, let t): t
        case .liveStream(_, _, _, _, let t): t
        default: nil
        }
    }

    /// True for sources that come from local disk and need no network.
    public var isLocal: Bool {
        switch self {
        case .localFile, .download, .cache: true
        case .remoteStream, .liveStream: false
        }
    }

    /// True for sources with a known finite duration that may be seekable.
    public var isFinite: Bool {
        switch self {
        case .localFile, .download, .cache, .remoteStream: true
        case .liveStream: false
        }
    }
}