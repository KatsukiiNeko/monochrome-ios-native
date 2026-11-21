// WidgetBridge.swift: publishes playback snapshots and coalesced widget reloads.
#if canImport(SwiftUI)
import Foundation
import MonochromeCore
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(ImageIO)
import ImageIO
#endif

/// One observation loop plus one reload governor. Position ticks wake the loop
/// but only state changes write a snapshot, so the widget budget stays small.
@MainActor
final class WidgetBridge {
    private static let kind = SnapshotStore.widgetKind

    private let player: PlayerController
    private let store: SnapshotStore
    private let mediaDirectory: URL

    private var pumpTask: Task<Void, Never>?
    private var wake: AsyncStream<Void>.Continuation?
    private var governor = ReloadGovernor()
    private var pendingReload: Task<Void, Never>?

    private var lastSignature: Signature?
    private var lastTrackID: String?
    private var playStartedAt: Date?
    private var artworkName: String?
    private var artworkTask: Task<Void, Never>?
    private var artworkNames: [String] = []

    private struct Signature: Equatable {
        var trackID: String?
        var phase: String
        var seekCount: Int
        var isPlaying: Bool
        var duration: Double
    }

    private struct Inputs {
        var track: Track?
        var phase: PlaybackState
        var seekCount: Int
        var duration: Double
        /// Read only so position ticks re-arm the loop and catch engine changes.
        var position: Double
    }

    init(player: PlayerController, store: SnapshotStore, mediaDirectory: URL) {
        self.player = player
        self.store = store
        self.mediaDirectory = mediaDirectory
    }

    func start() {
        guard pumpTask == nil else { return }
        writeSnapshot()
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        wake = continuation
        // The closure keeps a weak reference: the task is stored on self, so a
        // strong capture would be a cycle for the app's whole lifetime.
        pumpTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let recheck = Self.pass(self) else { return }
                if recheck {
                    // The engine reports pause a moment after the state flips,
                    // and no position tick follows. Settle the snapshot.
                    try? await Task.sleep(for: .milliseconds(300))
                    continue
                }
                for await _ in stream { break }
            }
        }
        widgetLog.notice("bridge start")
    }

    func stop() {
        pumpTask?.cancel()
        pumpTask = nil
        wake?.finish()
        wake = nil
        pendingReload?.cancel()
        pendingReload = nil
        artworkTask?.cancel()
        artworkTask = nil
    }

    /// One synchronous observation pass. Returns whether the pause needs a
    /// recheck, or nil once the bridge is gone. Keeping this static and scoped
    /// means the long-lived task holds only a weak reference.
    private static func pass(_ bridge: WidgetBridge?) -> Bool? {
        guard let bridge else { return nil }
        let wake = bridge.wake
        var inputs: Inputs?
        withObservationTracking {
            inputs = Inputs(
                track: bridge.player.currentTrack,
                phase: bridge.player.state,
                seekCount: bridge.player.seekCount,
                duration: bridge.player.duration,
                position: bridge.player.position
            )
        } onChange: {
            wake?.yield(())
        }
        if let inputs { bridge.apply(inputs) }
        return inputs?.phase == .paused && bridge.player.isEngineProducingAudio
    }

    private func apply(_ inputs: Inputs) {
        let isPlaying = player.isEngineProducingAudio
        let signature = Signature(
            trackID: inputs.track?.id,
            phase: inputs.phase.logName,
            seekCount: inputs.seekCount,
            isPlaying: isPlaying,
            duration: inputs.duration
        )
        guard signature != lastSignature else { return }
        lastSignature = signature
        updateTrackState(track: inputs.track, isPlaying: isPlaying, now: .now)
        writeSnapshot()
    }

    private func updateTrackState(track: Track?, isPlaying: Bool, now: Date) {
        guard let track else {
            lastTrackID = nil
            playStartedAt = nil
            artworkName = nil
            return
        }
        if track.id != lastTrackID {
            lastTrackID = track.id
            playStartedAt = isPlaying ? now : nil
            artworkName = nil
            prepareArtwork(for: track)
        } else if isPlaying {
            if playStartedAt == nil { playStartedAt = now }
        } else {
            // A resume is a new drop; the arm should land again.
            playStartedAt = nil
        }
    }

    private func writeSnapshot() {
        let now = Date()
        let track = player.currentTrack
        let isPlaying = player.isEngineProducingAudio
        updateTrackState(track: track, isPlaying: isPlaying, now: now)
        let previous = store.read()
        let duration = player.duration > 0 ? player.duration : track?.durationSeconds
        let position = min(max(player.position, 0), duration ?? .infinity)
        let snapshot = PlaybackSnapshot(
            trackID: track?.id,
            title: track?.title ?? "",
            artist: track?.displayArtist ?? "",
            duration: duration,
            position: position,
            isPlaying: isPlaying && track != nil,
            platterDegrees: previous?.platter(at: now) ?? 0,
            date: now,
            playStartedAt: playStartedAt,
            artworkFile: artworkName
        )
        do {
            try store.write(snapshot)
            widgetLog.notice(
                "[Widget] snapshot track=\(snapshot.trackID?.prefix(8).description ?? "-", privacy: .public) playing=\(snapshot.isPlaying, privacy: .public) duration=\(snapshot.duration ?? -1, privacy: .public) position=\(snapshot.position, privacy: .public)"
            )
            // A track that just started is the one reload that must not wait:
            // the arm drop only lasts a few seconds.
            let startedPlaying = snapshot.isPlaying && previous?.isPlaying != true
            reloadWidget(at: now, urgent: startedPlaying)
        } catch {
            widgetLog.error("snapshot write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func reloadWidget(at now: Date, urgent: Bool = false) {
        #if canImport(WidgetKit)
        switch governor.request(at: now, urgent: urgent) {
        case .now:
            pendingReload?.cancel()
            pendingReload = nil
            WidgetCenter.shared.reloadTimelines(ofKind: Self.kind)
        case .later(let date):
            pendingReload?.cancel()
            pendingReload = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
                guard !Task.isCancelled else { return }
                WidgetCenter.shared.reloadTimelines(ofKind: Self.kind)
                self?.pendingReload = nil
            }
        }
        #endif
    }

    private func prepareArtwork(for track: Track) {
        artworkTask?.cancel()
        let media = mediaDirectory
        artworkTask = Task { [weak self] in
            guard let data = await Self.loadArtworkData(for: track, media: media),
                  !Task.isCancelled,
                  let jpeg = await Task.detached(priority: .utility, operation: {
                      Self.downsampledJPEG(data)
                  }).value,
                  !Task.isCancelled
            else { return }
            let name = "artwork-\(Self.safeName(track.id)).jpg"
            guard let self else { return }
            do {
                try self.store.writeArtwork(jpeg, named: name)
            } catch {
                widgetLog.error("artwork write failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            self.artworkNames.append(name)
            if self.artworkNames.count > 3 {
                self.artworkNames.removeFirst(self.artworkNames.count - 3)
            }
            self.store.pruneArtwork(keeping: self.artworkNames)
            guard self.lastTrackID == track.id else { return }
            self.artworkName = name
            self.writeSnapshot()
        }
    }

    private nonisolated static func loadArtworkData(for track: Track, media: URL) async -> Data? {
        if let name = track.artworkFileName, !name.isEmpty {
            return try? Data(contentsOf: media.appendingPathComponent(name))
        }
        guard let url = track.artworkURL,
              let data = try? await URLSession.shared.data(from: url).0,
              data.count <= 8 * 1024 * 1024
        else { return nil }
        return data
    }

    /// One 256 px JPEG per track keeps the shared container small. ImageIO
    /// decodes only the thumbnail, so a huge remote image cannot balloon memory.
    private nonisolated static func downsampledJPEG(_ data: Data) -> Data? {
        #if canImport(UIKit) && canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else { return nil }
        return UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.8)
        #else
        return nil
        #endif
    }

    private nonisolated static func safeName(_ id: String) -> String {
        String(id.map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }
}
#endif
