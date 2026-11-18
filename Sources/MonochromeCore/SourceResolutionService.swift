// SourceResolutionService.swift: resolve the best candidate, then the next one.
import Foundation

public struct SourceResolutionService: Sendable {
    public var perPlayBudget: Int

    public init(perPlayBudget: Int = 3) {
        self.perPlayBudget = max(1, perPlayBudget)
    }

    /// Tries candidates in order until one resolves. Never loops beyond the
    /// budget. Cancellation aborts with no result.
    public func resolve(
        candidates: [SourceCandidate],
        resolve: @escaping (SourceCandidate) async throws -> PlaybackSource,
        isCancelled: @escaping () -> Bool = { false }
    ) async -> (candidate: SourceCandidate, source: PlaybackSource)? {
        var attempts = 0
        for candidate in candidates {
            if isCancelled() { return nil }
            if attempts >= perPlayBudget { break }
            attempts += 1
            do {
                let source = try await resolve(candidate)
                if isCancelled() { return nil }
                return (candidate, source)
            } catch {
                continue
            }
        }
        return nil
    }
}