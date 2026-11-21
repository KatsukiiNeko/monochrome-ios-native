// ReloadGovernor.swift: coalesces widget reload requests into one budget.
import Foundation

public enum ReloadDecision: Equatable, Sendable {
    case now
    case later(Date)
}

public struct ReloadGovernor: Sendable {
    public var minInterval: TimeInterval = 5
    private var lastReload: Date?

    public init() {}

    /// `.now` means reload; `.later` means schedule one deferred reload at the
    /// given date, replacing any pending one.
    public mutating func request(at now: Date) -> ReloadDecision {
        if let last = lastReload, now.timeIntervalSince(last) < minInterval {
            return .later(last.addingTimeInterval(minInterval))
        }
        lastReload = now
        return .now
    }
}
