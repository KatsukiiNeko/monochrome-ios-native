// CallbackRelay.swift: hops AVFoundation/NotificationCenter callbacks onto the main actor.
#if canImport(SwiftUI)
import Foundation

/// Callbacks from Apple frameworks arrive off the main actor and their closures are
/// @Sendable, so they capture this box instead of a view model or the player.
final class CallbackRelay<Value: Sendable>: @unchecked Sendable {
    var handler: ((Value) -> Void)?

    func send(_ value: Value) {
        Task { @MainActor in handler?(value) }
    }
}
#endif
