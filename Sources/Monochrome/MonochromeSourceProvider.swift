// MonochromeSourceProvider.swift: the catalog as a music source provider.
#if canImport(SwiftUI)
import Foundation
import MonochromeCore

struct MonochromeSourceProvider: MusicSourceProvider {
    let client: TracksAPIClient?

    var id: String { MusicSourceID.monochrome.rawValue }
    var displayName: String { MusicSourceID.monochrome.displayName }
    var capabilities: ProviderCapabilities { [.search, .browse, .audio] }

    func search(_ query: String, limit: Int) async throws -> [Track] {
        guard let client else { throw ProviderError.notConfigured }
        do {
            return try await client.searchTracks(matching: query, limit: limit)
        } catch let error as TracksAPIError {
            throw Self.map(error)
        }
    }

    func resolve(_ track: Track) async throws -> PlaybackSource {
        guard let client else { throw ProviderError.notConfigured }
        guard let url = await client.streamURL(for: track) else {
            throw ProviderError.unavailable
        }
        return .remoteStream(
            url: url,
            headers: [:],
            providerID: id,
            quality: track.audioQuality,
            contentType: DefaultTrackResolver.streamContentType
        )
    }

    private static func map(_ error: TracksAPIError) -> ProviderError {
        switch error {
        case .notConfigured: .notConfigured
        case .httpStatus(let code) where code == 401 || code == 403: .unauthorized
        case .httpStatus(let code) where code == 429: .rateLimited(retryAfter: nil)
        case .httpStatus: .transient(error.localizedDescription)
        case .unavailable: .unavailable
        case .invalidPayload: .transient(error.localizedDescription)
        }
    }
}
#endif