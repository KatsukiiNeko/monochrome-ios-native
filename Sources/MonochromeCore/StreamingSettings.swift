// StreamingSettings.swift: the user's streaming host, persisted in UserDefaults.
import Foundation

public struct StreamingSettings {
    public static let defaultBaseURL = URL(string: "https://tracks.monochrome.st")!
    public static let storageKey = "streaming.baseURL"
    public static let enabledKey = "streaming.enabled"
    public static let userHostsKey = "streaming.userHosts"
    public static let maximumUserHosts = 8

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The configured host, independent of whether streaming is enabled.
    public var configuredBaseURL: URL? {
        guard let raw = defaults.string(forKey: Self.storageKey) else { return Self.defaultBaseURL }
        return Self.baseURL(from: raw)
    }

    /// Older builds represented "off" as an empty host, so a missing toggle
    /// adopts that state instead of switching streaming back on.
    public var isEnabled: Bool {
        guard configuredBaseURL != nil else { return false }
        guard defaults.object(forKey: Self.enabledKey) != nil else { return true }
        return defaults.bool(forKey: Self.enabledKey)
    }

    /// `nil` means streaming is switched off; local playback still works.
    public var baseURL: URL? {
        isEnabled ? configuredBaseURL : nil
    }

    /// The stored text, shown in Settings. Never stored credentials: there are none.
    public var rawValue: String {
        defaults.string(forKey: Self.storageKey) ?? Self.defaultBaseURL.absoluteString
    }

    public func setBaseURL(_ raw: String) {
        defaults.set(raw.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.storageKey)
    }

    public func setEnabled(_ enabled: Bool) {
        // An enabled client needs a host. Recover the built-in default rather
        // than persisting an enabled state with no usable endpoint.
        if enabled, configuredBaseURL == nil {
            reset()
        }
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    // MARK: - Extra hosts

    /// User-supplied catalog hosts, tried before the default endpoint.
    public var userHosts: [URL] {
        (defaults.stringArray(forKey: Self.userHostsKey) ?? [])
            .compactMap { Self.baseURL(from: $0) }
    }

    /// User hosts first, then the configured endpoint, then the built-in default.
    /// Duplicates are dropped so a host never takes two turns.
    public var allHosts: [URL] {
        var ordered: [URL] = []
        var seen: Set<String> = []
        for url in userHosts + [configuredBaseURL, Self.defaultBaseURL].compactMap({ $0 }) {
            if seen.insert(url.absoluteString).inserted {
                ordered.append(url)
            }
        }
        return ordered
    }

    /// HTTPS only. Returns false for an invalid or already-listed host, or at the cap.
    @discardableResult
    public func addUserHost(_ raw: String) -> Bool {
        guard let url = Self.baseURL(from: raw) else { return false }
        var hosts = userHosts
        guard hosts.count < Self.maximumUserHosts,
              !hosts.contains(where: { $0.absoluteString == url.absoluteString }) else { return false }
        hosts.append(url)
        defaults.set(hosts.map(\.absoluteString), forKey: Self.userHostsKey)
        return true
    }

    public func removeUserHost(at index: Int) {
        var hosts = userHosts
        guard hosts.indices.contains(index) else { return }
        hosts.remove(at: index)
        defaults.set(hosts.map(\.absoluteString), forKey: Self.userHostsKey)
    }

    public func moveUserHost(from source: Int, to destination: Int) {
        var hosts = userHosts
        guard hosts.indices.contains(source), (0...hosts.count).contains(destination) else { return }
        let moved = hosts.remove(at: source)
        let adjusted = destination > source ? destination - 1 : destination
        hosts.insert(moved, at: min(adjusted, hosts.count))
        defaults.set(hosts.map(\.absoluteString), forKey: Self.userHostsKey)
    }

    public func resetUserHosts() {
        defaults.removeObject(forKey: Self.userHostsKey)
    }

    /// True when the stored host is an override rather than the built-in default.
    public var hasCustomEndpoint: Bool {
        guard let configured = configuredBaseURL else { return false }
        return configured != Self.defaultBaseURL
    }

    /// Restores the endpoint only. The effective enabled preference is preserved,
    /// including the legacy empty-host representation of "off".
    public func reset() {
        let wasEnabled = isEnabled
        defaults.removeObject(forKey: Self.storageKey)
        if !wasEnabled {
            defaults.set(false, forKey: Self.enabledKey)
        }
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
