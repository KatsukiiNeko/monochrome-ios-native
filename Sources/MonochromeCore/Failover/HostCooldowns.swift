// HostCooldowns.swift: per-host backoff so one failing host is not retried on
// every request. Delays double from 30 seconds and stop at ten minutes.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HostCooldowns: Sendable, Equatable {
    public static let baseDelay: TimeInterval = 30
    public static let maximumDelay: TimeInterval = 600

    private var failures: [String: Int] = [:]
    private var until: [String: Date] = [:]

    public init() {}

    public func isCoolingDown(_ host: URL, at date: Date) -> Bool {
        guard let deadline = until[host.absoluteString] else { return false }
        return deadline > date
    }

    public func failureCount(_ host: URL) -> Int {
        failures[host.absoluteString] ?? 0
    }

    /// A failure doubles the delay. A server's Retry-After wins when it asks for
    /// a longer wait than the backoff.
    public mutating func penalize(_ host: URL, at date: Date, minimum: TimeInterval = 0) {
        let key = host.absoluteString
        let count = (failures[key] ?? 0) + 1
        failures[key] = count
        let backoff = min(Self.baseDelay * pow(2, Double(count - 1)), Self.maximumDelay)
        until[key] = date.addingTimeInterval(max(backoff, minimum))
    }

    public mutating func reset(_ host: URL) {
        failures[host.absoluteString] = nil
        until[host.absoluteString] = nil
    }

    /// Seconds or an HTTP date. `nil` means the server did not say.
    public static func retryAfter(from response: HTTPURLResponse, at date: Date = .now) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty else { return nil }
        if let seconds = TimeInterval(raw), seconds >= 0 {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let deadline = formatter.date(from: raw) else { return nil }
        return max(0, deadline.timeIntervalSince(date))
    }
}
