// StreamingSettings.swift: the user's streaming host, persisted in UserDefaults.
import Foundation

public struct StreamingSettings {
    public static let defaultBaseURL = URL(string: "https://tracks.monochrome.st")!
    public static let storageKey = "streaming.baseURL"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `nil` means streaming is switched off; local playback still works.
    public var baseURL: URL? {
        guard let raw = defaults.string(forKey: Self.storageKey) else { return Self.defaultBaseURL }
        return Self.baseURL(from: raw)
    }

    /// The stored text, shown in Settings. Never stored credentials: there are none.
    public var rawValue: String {
        defaults.string(forKey: Self.storageKey) ?? Self.defaultBaseURL.absoluteString
    }

    public func setBaseURL(_ raw: String) {
        defaults.set(raw.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.storageKey)
    }

    public func reset() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    /// HTTPS only: the app ships no ATS exception.
    public static func baseURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              url.scheme == "https",
              let host = url.host,
              !host.isEmpty else { return nil }
        return url
    }
}
