// TasteProfile.swift: turn the event log into artist, album and track affinities.
import Foundation

/// Signal weights, kept in one place so the scoring is easy to read.
public enum TasteSignal {
    public static let completed = 1.0
    public static let favorite = 3.0
    public static let download = 2.0
    public static let loop = 0.5
    public static let moreLikeThis = 2.0
    public static let notForMeTrack = -4.0
    public static let notForMeArtist = -1.0
    public static let skip = -1.0
    /// Hearing the same track again counts as a replay.
    public static let replay = 0.5
    /// A skip counts only below this many seconds.
    public static let skipSecondThreshold = 30.0
    /// A skip counts only below this fraction of the track.
    public static let skipFractionThreshold = 0.25
    /// Affinity shrinks toward zero with this many observations.
    public static let shrinkage = 3.0
    /// Half-life of the time decay, in days.
    public static let halfLifeDays = 45.0
}

/// The aggregated taste of one listener.
public struct TasteProfile: Equatable, Sendable {
    public var trackAffinity: [String: Double]
    public var artistAffinity: [String: Double]
    public var albumAffinity: [String: Double]
    /// How often each track was played, for the repeat penalty.
    public var playCounts: [String: Int]
    public var eventCount: Int

    public init(
        trackAffinity: [String: Double] = [:],
        artistAffinity: [String: Double] = [:],
        albumAffinity: [String: Double] = [:],
        playCounts: [String: Int] = [:],
        eventCount: Int = 0
    ) {
        self.trackAffinity = trackAffinity
        self.artistAffinity = artistAffinity
        self.albumAffinity = albumAffinity
        self.playCounts = playCounts
        self.eventCount = eventCount
    }

    public var isColdStart: Bool { eventCount < TasteProfile.coldStartEventCount }

    /// Below this many events the app shows an empty state instead of guesses.
    public static let coldStartEventCount = 20

    public func artistScore(_ artist: String) -> Double {
        TasteProfile.shrunk(artistAffinity[artist.lowercased()] ?? 0)
    }

    public func albumScore(_ album: String) -> Double {
        TasteProfile.shrunk(albumAffinity[album.lowercased()] ?? 0)
    }

    public func trackScore(_ key: String) -> Double {
        TasteProfile.shrunk(trackAffinity[key] ?? 0)
    }

    /// Shrinks a raw affinity toward zero: A / (A + k), sign kept.
    public static func shrunk(_ raw: Double) -> Double {
        guard raw != 0 else { return 0 }
        return raw / (abs(raw) + TasteSignal.shrinkage)
    }

    /// The artists with the strongest taste, strongest first.
    public var topArtists: [String] {
        artistAffinity
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map(\.key)
    }

    public var topAlbums: [String] {
        albumAffinity
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map(\.key)
    }
    /// Builds the profile from the event log. Older events count less.
    public static func build(events: [PlayEvent], now: Date) -> TasteProfile {
        var profile = TasteProfile()
        profile.eventCount = events.count
        var artists: [String: Double] = [:]
        var albums: [String: Double] = [:]
        var tracks: [String: Double] = [:]
        /// How often each track was heard to the end; the first play counts
        /// as a completion, every later one as a replay.
        var completions: [String: Int] = [:]
        for event in events {
            let ageDays = max(0, now.timeIntervalSince(event.startedAt) / 86_400)
            let decay = pow(0.5, ageDays / TasteSignal.halfLifeDays)
            let artist = event.artist.lowercased()
            let album = event.album.lowercased()
            let track = event.trackKey

            switch event.outcome {
            case .completed:
                let plays = completions[track, default: 0]
                completions[track] = plays + 1
                let weight = plays == 0 ? TasteSignal.completed : TasteSignal.replay
                let value = weight * event.listenedFraction * decay
                add(value: value, to: &artists, key: artist)
                add(value: value, to: &albums, key: album)
                add(value: value, to: &tracks, key: track)
                profile.playCounts[track, default: 0] += 1
            case .skipped:
                // Only an early skip says something about the taste; without a
                // known duration only the heard seconds count.
                let early = event.listenedSeconds < TasteSignal.skipSecondThreshold
                    || (event.duration > 0
                        && event.listenedFraction < TasteSignal.skipFractionThreshold)
                guard early else { continue }
                add(value: TasteSignal.skip * decay, to: &artists, key: artist)
                add(value: TasteSignal.skip * decay, to: &tracks, key: track)
            case .favorited:
                add(value: TasteSignal.favorite * decay, to: &artists, key: artist)
                add(value: TasteSignal.favorite * decay, to: &albums, key: album)
                add(value: TasteSignal.favorite * decay, to: &tracks, key: track)
            case .downloaded:
                add(value: TasteSignal.download * decay, to: &artists, key: artist)
                add(value: TasteSignal.download * decay, to: &tracks, key: track)
            case .moreLikeThis:
                add(value: TasteSignal.moreLikeThis * decay, to: &artists, key: artist)
                add(value: TasteSignal.moreLikeThis * decay, to: &tracks, key: track)
            case .notForMe:
                add(value: TasteSignal.notForMeTrack * decay, to: &tracks, key: track)
                add(value: TasteSignal.notForMeArtist * decay, to: &artists, key: artist)
            }

            if event.loop {
                add(value: TasteSignal.loop * decay, to: &artists, key: artist)
                add(value: TasteSignal.loop * decay, to: &tracks, key: track)
            }
        }
        profile.artistAffinity = artists
        profile.albumAffinity = albums
        profile.trackAffinity = tracks
        return profile
    }

    /// Adds a raw signal; the shrinkage is applied when the score is read.
    private static func add(
        value: Double,
        to table: inout [String: Double],
        key: String
    ) {
        guard !key.isEmpty, value != 0 else { return }
        table[key, default: 0] += value
    }
}
