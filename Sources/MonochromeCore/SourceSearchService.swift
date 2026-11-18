// SourceSearchService.swift: fan a query out to every enabled provider.
import Foundation

public struct ProviderSearchResult: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case pending, partial, complete, failed
    }
    public var providerID: String
    public var status: Status
    public var tracks: [Track]
    public var error: ProviderError?

    public init(providerID: String, status: Status = .pending, tracks: [Track] = [], error: ProviderError? = nil) {
        self.providerID = providerID
        self.status = status
        self.tracks = tracks
        self.error = error
    }
}

public struct SourceSearchService: Sendable {
    /// Per-provider time budget; a search that exceeds it is treated as failed.
    public var perProviderBudget: Duration = .seconds(3)

    public init(perProviderBudget: Duration = .seconds(3)) {
        self.perProviderBudget = perProviderBudget
    }

    /// Queries all providers concurrently. One failure does not block the others.
    /// Empty results are only final once every provider has completed.
    public func search(
        query: String,
        limit: Int,
        providers: [any MusicSourceProvider]
    ) async -> [ProviderSearchResult] {
        await withTaskGroup(of: ProviderSearchResult.self) { group in
            for provider in providers {
                group.addTask {
                    await self.searchOne(provider: provider, query: query, limit: limit)
                }
            }
            var results: [ProviderSearchResult] = []
            for await result in group {
                results.append(result)
            }
            // Keep provider order stable for callers.
            let order = providers.map(\.id)
            return results.sorted { a, b in
                (order.firstIndex(of: a.providerID) ?? .max) < (order.firstIndex(of: b.providerID) ?? .max)
            }
        }
    }

    private func searchOne(provider: any MusicSourceProvider, query: String, limit: Int) async -> ProviderSearchResult {
        let outcome = await withTaskGroup(of: ProviderSearchResult.self) { group in
            group.addTask {
                do {
                    let tracks = try await provider.search(query, limit: limit)
                    return ProviderSearchResult(providerID: provider.id, status: .complete, tracks: tracks)
                } catch let error as ProviderError {
                    return ProviderSearchResult(providerID: provider.id, status: .failed, error: error)
                } catch {
                    return ProviderSearchResult(providerID: provider.id, status: .failed, error: .transient(error.localizedDescription))
                }
            }
            group.addTask {
                try? await Task.sleep(for: perProviderBudget)
                return ProviderSearchResult(providerID: provider.id, status: .failed, error: .transient("Timed out."))
            }
            let first = await group.next() ?? ProviderSearchResult(providerID: provider.id, status: .failed)
            group.cancelAll()
            return first
        }
        return outcome
    }
}