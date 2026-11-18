// LocalFileSourceProvider.swift: files on disk as a music source.
#if canImport(SwiftUI)
import Foundation
import MonochromeCore

struct LocalFileSourceProvider: MusicSourceProvider {
    let directory: URL

    var id: String { Track.localProvider }
    var displayName: String { "Local files" }
    var capabilities: ProviderCapabilities { [.audio, .browse] }

    func search(_ query: String, limit: Int) async throws -> [Track] { [] }

    func resolve(_ track: Track) async throws -> PlaybackSource {
        guard !track.fileName.isEmpty else { throw ProviderError.notConfigured }
        let url = directory.appendingPathComponent(track.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProviderError.unavailable
        }
        if track.provider == Track.localProvider {
            return .localFile(url: url, providerID: id, quality: track.audioQuality)
        }
        return .download(url: url, providerID: id, quality: track.audioQuality)
    }
}
#endif