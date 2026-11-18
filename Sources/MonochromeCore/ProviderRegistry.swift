// ProviderRegistry.swift: enabled providers in the listener's chosen order.
import Foundation

public struct ProviderRegistryEntry: Codable, Equatable, Sendable {
    public var id: String
    public var enabled: Bool

    public init(id: String, enabled: Bool = true) {
        self.id = id
        self.enabled = enabled
    }
}

public struct ProviderRegistryContent: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public var schemaVersion: Int
    public var entries: [ProviderRegistryEntry]

    public init(entries: [ProviderRegistryEntry] = []) {
        self.schemaVersion = Self.schemaVersion
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, entries }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.schemaVersion
        entries = try container.decodeIfPresent([ProviderRegistryEntry].self, forKey: .entries) ?? []
    }
}

/// Holds the enabled set and priority order of providers, persisted through the
/// shared JSON store. Unknown ids in the file are dropped; missing providers
/// default to enabled.
public struct ProviderRegistry: Sendable {
    public let providers: [any MusicSourceProvider]
    private let file: JSONFileStore
    private let now: @Sendable () -> Date
    private let log: (@Sendable (String) -> Void)?

    public init(
        providers: [any MusicSourceProvider],
        fileURL: URL,
        now: @escaping @Sendable () -> Date = { .now },
        log: (@Sendable (String) -> Void)? = nil
    ) {
        self.providers = providers
        self.file = JSONFileStore(fileURL: fileURL, maxBytes: 1 * 1024 * 1024, now: now, log: log)
        self.now = now
        self.log = log
    }

    private func loadEntries() -> [ProviderRegistryEntry] {
        let known = Set(providers.map(\.id))
        guard let content = file.read(ProviderRegistryContent.self) else {
            return providers.map { ProviderRegistryEntry(id: $0.id, enabled: true) }
        }
        // Keep only known providers; append any new ones as enabled.
        var entries = content.entries.filter { known.contains($0.id) }
        for provider in providers where !entries.contains(where: { $0.id == provider.id }) {
            entries.append(ProviderRegistryEntry(id: provider.id, enabled: true))
        }
        return entries
    }

    private func saveEntries(_ entries: [ProviderRegistryEntry]) {
        do {
            try file.write(ProviderRegistryContent(entries: entries))
        } catch {
            log?("provider registry save failed: \(error.localizedDescription)")
        }
    }

    public func all() -> [ProviderRegistryEntry] { loadEntries() }

    public func isEnabled(_ id: String) -> Bool {
        loadEntries().first { $0.id == id }?.enabled ?? true
    }

    public func enabledProviders() -> [any MusicSourceProvider] {
        let entries = loadEntries()
        var result: [any MusicSourceProvider] = []
        for entry in entries where entry.enabled {
            if let provider = providers.first(where: { $0.id == entry.id }) {
                result.append(provider)
            }
        }
        return result
    }

    public func setEnabled(_ id: String, enabled: Bool) {
        var entries = loadEntries()
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].enabled = enabled
        } else {
            entries.append(ProviderRegistryEntry(id: id, enabled: enabled))
        }
        saveEntries(entries)
    }

    public func move(from source: Int, to destination: Int) {
        var entries = loadEntries()
        guard entries.indices.contains(source),
              destination >= 0, destination <= entries.count else { return }
        let item = entries.remove(at: source)
        let target = destination > source ? destination - 1 : destination
        entries.insert(item, at: min(target, entries.count))
        saveEntries(entries)
    }
}