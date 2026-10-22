// URLSessionFileDownloader.swift: streams one file to disk for the audio cache.
#if os(iOS)
import Foundation
import MonochromeCore

struct URLSessionFileDownloader: FileDownloader {
    /// Read per download so a Settings change applies without rebuilding the cache.
    let allowsCellular: @Sendable () -> Bool

    func download(
        from url: URL,
        to destination: URL,
        allowsExpensiveNetwork: Bool
    ) async throws -> DownloadResult {
        var request = URLRequest(url: url)
        // Caching must never silently double mobile data; the caller decides.
        let expensive = allowsExpensiveNetwork && allowsCellular()
        request.allowsExpensiveNetworkAccess = expensive
        request.allowsConstrainedNetworkAccess = expensive
        request.timeoutInterval = 60

        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: temporary)
            throw URLError(.badServerResponse)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: temporary.path)
        let bytes = (attributes[.size] as? NSNumber)?.intValue ?? 0
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        let expected = http.expectedContentLength > 0 ? Int(http.expectedContentLength) : nil
        return DownloadResult(bytesWritten: bytes, expectedBytes: expected)
    }
}
#endif
