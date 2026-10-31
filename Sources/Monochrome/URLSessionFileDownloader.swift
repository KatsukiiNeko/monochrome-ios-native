// URLSessionFileDownloader.swift: streams one file to disk for cache or downloads.
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
        try await ProgressTransfer(
            url: url,
            destination: destination,
            allowsExpensiveNetwork: allowsExpensiveNetwork && allowsCellular(),
            onProgress: { _, _ in }
        ).run()
    }

    func download(
        from url: URL,
        to destination: URL,
        allowsExpensiveNetwork: Bool,
        onProgress: @escaping @Sendable (Int, Int?) -> Void
    ) async throws -> DownloadResult {
        try await ProgressTransfer(
            url: url,
            destination: destination,
            allowsExpensiveNetwork: allowsExpensiveNetwork && allowsCellular(),
            onProgress: onProgress
        ).run()
    }
}

/// One download task with real byte progress. The caller owns the partial file.
private final class ProgressTransfer: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let url: URL
    private let destination: URL
    private let allowsExpensiveNetwork: Bool
    private let onProgress: @Sendable (Int, Int?) -> Void
    private var session: URLSession?
    private var continuation: CheckedContinuation<DownloadResult, Error>?

    init(
        url: URL,
        destination: URL,
        allowsExpensiveNetwork: Bool,
        onProgress: @escaping @Sendable (Int, Int?) -> Void
    ) {
        self.url = url
        self.destination = destination
        self.allowsExpensiveNetwork = allowsExpensiveNetwork
        self.onProgress = onProgress
    }

    func run() async throws -> DownloadResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.default
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            var request = URLRequest(url: url)
            // The catalog host accepts the app's own identity; URLSession's default
            // CFNetwork identity is not the one the API and player use.
            request.setValue(TracksAPIClient.userAgent, forHTTPHeaderField: "User-Agent")
            request.allowsExpensiveNetworkAccess = allowsExpensiveNetwork
            request.allowsConstrainedNetworkAccess = allowsExpensiveNetwork
            request.timeoutInterval = 60
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0 ? Int(totalBytesExpectedToWrite) : nil
        onProgress(Int(totalBytesWritten), expected)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let http = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: location)
            finish(.failure(URLError(.badServerResponse)))
            return
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: location.path)
        let bytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            finish(.failure(error))
            return
        }
        let expected = http.expectedContentLength > 0 ? Int(http.expectedContentLength) : nil
        finish(.success(DownloadResult(bytesWritten: bytes, expectedBytes: expected)))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let error else { return }
        finish(.failure(error))
    }

    private func finish(_ result: Result<DownloadResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        session?.finishTasksAndInvalidate()
        session = nil
        continuation.resume(with: result)
    }
}
#endif
