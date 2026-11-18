// NetworkMonitor.swift: whether the current path is unmetered Wi-Fi.
#if canImport(Network)
import Foundation
import Network
import MonochromeCore

final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "monochrome.network")
    private var path: NWPath?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in self?.path = path }
        monitor.start(queue: queue)
    }

    var isUnmeteredWiFi: Bool {
        guard let path, path.status == .satisfied else { return false }
        if path.isExpensive { return false }
        if path.usesInterfaceType(.cellular) { return false }
        return path.usesInterfaceType(.wifi)
    }
}
#endif