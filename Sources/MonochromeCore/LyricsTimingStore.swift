// LyricsTimingStore.swift: the manual lyrics offset per track, in UserDefaults.
import Foundation

/// Offsets are clamped to a range the app can usefully compensate for.
public struct LyricsTimingStore {
    public static let maximumDelay: TimeInterval = 5
    public static let keyPrefix = "lyrics.timingDelay."

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// A missing value reads as zero, so an in-sync track stores no key.
    public func delay(for trackID: String?) -> TimeInterval {
        let stored = defaults.double(forKey: key(for: trackID))
        return min(max(stored, -Self.maximumDelay), Self.maximumDelay)
    }

    /// Stores the offset and returns the clamped value that was written.
    @discardableResult
    public func setDelay(_ value: TimeInterval, for trackID: String?) -> TimeInterval {
        let clamped = min(max(value, -Self.maximumDelay), Self.maximumDelay)
        if clamped == 0 {
            defaults.removeObject(forKey: key(for: trackID))
        } else {
            defaults.set(clamped, forKey: key(for: trackID))
        }
        return clamped
    }

    private func key(for trackID: String?) -> String {
        Self.keyPrefix + (trackID ?? "none")
    }
}
