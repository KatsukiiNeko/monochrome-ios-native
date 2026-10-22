// MetadataReader.swift: reads title/artist/album/duration tags from an audio file.
#if canImport(AVFoundation)
import AVFoundation
import Foundation
import MonochromeCore

struct AVAssetMetadataReader: TrackMetadataReading {
    func metadata(for url: URL) async -> TrackMetadata? {
        let asset = AVURLAsset(url: url)

        var title: String?
        var artist: String?
        var album: String?
        var artworkData: Data?
        // Format-specific tags (FLAC/ID3/iTunes) are searched too, since
        // commonMetadata alone is often empty for FLAC files.
        if let items = try? await asset.load(.metadata) {
            for item in items {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    title = (try? await item.load(.stringValue)) ?? title
                case .commonKeyArtist:
                    artist = (try? await item.load(.stringValue)) ?? artist
                case .commonKeyAlbumName:
                    album = (try? await item.load(.stringValue)) ?? album
                case .commonKeyArtwork:
                    artworkData = (try? await item.load(.dataValue)) ?? artworkData
                default:
                    break
                }
            }
        }

        let duration = try? await asset.load(.duration)

        return TrackMetadata(
            title: cleaned(title),
            artist: cleaned(artist),
            album: cleaned(album),
            durationSeconds: duration.map { $0.seconds },
            artworkData: artworkData
        )
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
#endif
