// AppearanceSettings.swift: the user's System/Light/Dark preference, persisted in UserDefaults.
import Foundation

public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

public struct AppearanceSettings {
    public static let storageKey = "appearance.mode"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Unknown or missing values follow the system, which is the safe default.
    public var mode: AppearanceMode {
        guard let raw = defaults.string(forKey: Self.storageKey),
              let mode = AppearanceMode(rawValue: raw) else { return .system }
        return mode
    }

    public func setMode(_ mode: AppearanceMode) {
        defaults.set(mode.rawValue, forKey: Self.storageKey)
    }

    public func reset() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
