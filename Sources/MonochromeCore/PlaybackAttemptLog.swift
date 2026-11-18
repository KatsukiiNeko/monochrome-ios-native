// PlaybackAttemptLog.swift: one play attempt's phases and timings, safe to log.
import Foundation

public enum PlaybackPhase: String, CaseIterable, Sendable, Equatable {
    /// The listener asked for this track.
    case tap
    /// Downloads and cache were checked.
    case lookup
    /// A stream URL and MIME type were resolved.
    case resolve
    /// An asset/item was handed to the engine.
    case asset
    /// The engine reported the item ready.
    case ready
    /// The attempt ended with an error.
    case failed
}

/// A small state machine for one attempt. It stores only phase times, a short
/// track hash and per-consumer request counts, so a summary line never carries
/// a URL, a title or an account.
public struct PlaybackAttemptLog: Sendable, Equatable {
    public struct Event: Equatable, Sendable {
        public var phase: PlaybackPhase
        public var at: Date
        /// Short, non-identifying note such as "cache-hit" or "NSURLErrorDomain/-1008".
        public var detail: String?

        public init(phase: PlaybackPhase, at: Date, detail: String? = nil) {
            self.phase = phase
            self.at = at
            self.detail = detail
        }
    }

    public let attemptID: UUID
    /// Eight hex characters of the provider and track id.
    public let trackKeyHash: String
    public let startedAt: Date
    public private(set) var events: [Event]
    /// Requests per consumer for this attempt.
    public private(set) var requests: [String: Int] = [:]

    public init(trackKey: String, at date: Date, attemptID: UUID = UUID()) {
        self.attemptID = attemptID
        self.trackKeyHash = Self.hash(trackKey)
        self.startedAt = date
        self.events = [Event(phase: .tap, at: date)]
    }

    public mutating func mark(_ phase: PlaybackPhase, at date: Date, detail: String? = nil) {
        events.append(Event(phase: phase, at: date, detail: detail))
    }

    public mutating func countRequest(_ consumer: String) {
        requests[consumer, default: 0] += 1
    }

    /// Milliseconds spent in the last occurrence of a phase: the gap from the
    /// event before it. A retried lookup therefore measures only that lookup.
    public func durationMs(of phase: PlaybackPhase) -> Int? {
        guard let index = events.lastIndex(where: { $0.phase == phase }), index > 0 else { return nil }
        return Self.milliseconds(events[index - 1].at, events[index].at)
    }

    /// Milliseconds from the tap to the last occurrence of a phase.
    public func elapsedMs(to phase: PlaybackPhase) -> Int? {
        guard let event = events.last(where: { $0.phase == phase }) else { return nil }
        return Self.milliseconds(startedAt, event.at)
    }

    public var isFailed: Bool {
        events.contains { $0.phase == .failed }
    }

    /// One line: attempt id, track hash, per-phase durations, error shape and
    /// request counts. No URL, title, server or listener data.
    public var summary: String {
        var parts = [
            "attempt=\(attemptID.uuidString.prefix(8))",
            "track=\(trackKeyHash)",
        ]
        if let lookup = events.last(where: { $0.phase == .lookup }) {
            parts.append("lookup=\(durationMs(of: .lookup) ?? 0)ms")
            parts.append(lookup.detail ?? "miss")
        }
        if events.contains(where: { $0.phase == .resolve }) {
            parts.append("resolve=\(durationMs(of: .resolve) ?? 0)ms")
        }
        if events.contains(where: { $0.phase == .asset }) {
            parts.append("asset=\(durationMs(of: .asset) ?? 0)ms")
        }
        if let ready = events.last(where: { $0.phase == .ready }) {
            parts.append("ready=\(elapsedMs(to: .ready) ?? 0)ms")
            if let detail = ready.detail { parts.append("via=\(detail)") }
        }
        if let failed = events.last(where: { $0.phase == .failed }) {
            parts.append("failed=\(elapsedMs(to: .failed) ?? 0)ms")
            if let detail = failed.detail { parts.append("error=\(detail)") }
        }
        if !requests.isEmpty {
            let counts = requests
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ",")
            parts.append("requests=\(counts)")
        }
        return parts.joined(separator: " ")
    }

    /// Error domain and code, including one underlying level. Descriptions are
    /// dropped because a framework description can embed the failing URL.
    public static func errorDetail(_ error: any Error) -> String {
        let nsError = error as NSError
        var text = "\(nsError.domain)/\(nsError.code)"
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            text += " under=\(underlying.domain)/\(underlying.code)"
        }
        return text
    }

    /// Eight hex characters, enough to follow one track across attempts.
    public static func hash(_ key: String) -> String {
        SHA256.digest(Data(key.utf8)).prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func milliseconds(_ start: Date, _ end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) * 1000).rounded()))
    }
}
