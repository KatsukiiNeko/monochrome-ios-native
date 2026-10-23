// AudioCacheSettings.swift: user preference for caching audio over cellular.
import Foundation

public struct AudioCacheSettings {
    public static let storageKey = "cache.allowsCellular"
    public static let clearOnLaunchKey = "cache.clearOnLaunch"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Off by default so caching never adds mobile data without being asked.
    public var allowsCellular: Bool {
        defaults.bool(forKey: Self.storageKey)
    }

    public func setAllowsCellular(_ allowed: Bool) {
        defaults.set(allowed, forKey: Self.storageKey)
    }

    /// Off by default: valid entries survive a relaunch so a recent song starts instantly.
    public var clearOnLaunch: Bool {
        defaults.bool(forKey: Self.clearOnLaunchKey)
    }

    public func setClearOnLaunch(_ clear: Bool) {
        defaults.set(clear, forKey: Self.clearOnLaunchKey)
    }
}
