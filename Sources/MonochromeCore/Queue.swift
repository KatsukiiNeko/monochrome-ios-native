// Queue.swift: ordered track list with a cursor; no playback knowledge.
import Foundation

public struct Queue: Equatable, Sendable {
    public private(set) var tracks: [Track] = []
    public private(set) var currentIndex: Int?

    public init(tracks: [Track] = []) {
        self.tracks = tracks
        self.currentIndex = tracks.isEmpty ? nil : 0
    }

    public var current: Track? {
        guard let currentIndex, tracks.indices.contains(currentIndex) else { return nil }
        return tracks[currentIndex]
    }

    public var isEmpty: Bool { tracks.isEmpty }
    public var canAdvance: Bool {
        guard let currentIndex else { return false }
        return currentIndex + 1 < tracks.count
    }
    public var canRewind: Bool {
        guard let currentIndex else { return false }
        return currentIndex > 0
    }

    public mutating func replace(with tracks: [Track], startingAt index: Int) {
        self.tracks = tracks
        guard !tracks.isEmpty else {
            currentIndex = nil
            return
        }
        currentIndex = min(max(index, 0), tracks.count - 1)
    }

    public mutating func append(_ newTracks: [Track]) {
        tracks.append(contentsOf: newTracks)
        if currentIndex == nil, !tracks.isEmpty {
            currentIndex = 0
        }
    }

    /// Removes a track and keeps the cursor on the same logical item where possible.
    @discardableResult
    public mutating func remove(at index: Int) -> Track? {
        guard tracks.indices.contains(index) else { return nil }
        let removed = tracks.remove(at: index)
        guard let cursor = currentIndex else { return removed }

        if tracks.isEmpty {
            currentIndex = nil
        } else if index < cursor {
            currentIndex = cursor - 1
        } else if index == cursor {
            // The cursor now names the following track, clamped to the new end.
            currentIndex = min(index, tracks.count - 1)
        }
        return removed
    }

    public mutating func jump(to index: Int) -> Track? {
        guard tracks.indices.contains(index) else { return nil }
        currentIndex = index
        return tracks[index]
    }

    /// `destination` follows Array.move semantics: the index the track would occupy
    /// before it is lifted out, so moving down shifts by one.
    public mutating func move(from source: Int, to destination: Int) {
        guard tracks.indices.contains(source), (0...tracks.count).contains(destination) else { return }
        let currentID = current?.id
        let moved = tracks.remove(at: source)
        let adjusted = destination > source ? destination - 1 : destination
        tracks.insert(moved, at: min(adjusted, tracks.count))
        if let currentID {
            currentIndex = tracks.firstIndex { $0.id == currentID }
        }
    }

    public mutating func advance() -> Track? {
        guard let cursor = currentIndex, cursor + 1 < tracks.count else { return nil }
        currentIndex = cursor + 1
        return tracks[cursor + 1]
    }

    public mutating func rewind() -> Track? {
        guard let cursor = currentIndex, cursor > 0 else { return nil }
        currentIndex = cursor - 1
        return tracks[cursor - 1]
    }
}
