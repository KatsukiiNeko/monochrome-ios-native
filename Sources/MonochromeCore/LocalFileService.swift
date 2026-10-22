// LocalFileService.swift: imports audio files into app storage and owns the library.
import Foundation

public struct LocalFileService: MusicService {
    public let mediaDirectory: URL
    public let store: LibraryStore
    private let metadataReader: any TrackMetadataReading

    public init(mediaDirectory: URL, store: LibraryStore, metadataReader: any TrackMetadataReading) {
        self.mediaDirectory = mediaDirectory
        self.store = store
        self.metadataReader = metadataReader
    }

    public func allTracks() async throws -> [Track] {
        try store.load().sorted { $0.importedAt > $1.importedAt }
    }

    /// Copies the file into app-owned storage so playback never depends on the
    /// picker's security-scoped access, then records the track.
    public func importTrack(from url: URL, fallbackTitle: String?) async throws -> Track {
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)

        let id = UUID().uuidString
        let ext = url.pathExtension.isEmpty ? "audio" : url.pathExtension
        let fileName = "\(id).\(ext)"
        let destination = mediaDirectory.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: url, to: destination)

        let metadata = await metadataReader.metadata(for: destination)
        let title = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines)

        let artworkFileName: String?
        if let artworkData = metadata?.artworkData, !artworkData.isEmpty {
            let name = "\(id).artwork"
            try artworkData.write(to: mediaDirectory.appendingPathComponent(name), options: .atomic)
            artworkFileName = name
        } else {
            artworkFileName = nil
        }

        let track = Track(
            id: id,
            title: title.flatMap { $0.isEmpty ? nil : $0 }
                ?? fallbackTitle
                ?? url.deletingPathExtension().lastPathComponent,
            artist: metadata?.artist ?? "",
            album: metadata?.album ?? "",
            durationSeconds: metadata?.durationSeconds,
            fileName: fileName,
            artworkFileName: artworkFileName
        )

        var tracks = try store.load()
        tracks.insert(track, at: 0)
        try store.save(tracks)
        return track
    }

    public func delete(_ track: Track) async throws {
        var tracks = try store.load()
        tracks.removeAll { $0.id == track.id }
        try store.save(tracks)
        // A missing file is already the desired state.
        try? FileManager.default.removeItem(at: mediaDirectory.appendingPathComponent(track.fileName))
        if let artworkFileName = track.artworkFileName {
            try? FileManager.default.removeItem(at: mediaDirectory.appendingPathComponent(artworkFileName))
        }
    }
}
