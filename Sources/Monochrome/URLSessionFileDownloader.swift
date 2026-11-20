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
        try await transfer(
            from: url,
            to: destination,
            allowsExpensiveNetwork: allowsExpensiveNetwork && allowsCellular(),
            onProgress: { _, _ in }
        )
    }

    func download(
        from url: URL,
        to destination: URL,
        allowsExpensiveNetwork: Bool,
        onProgress: @escaping @Sendable (Int, Int?) -> Void
    ) async throws -> DownloadResult {
        try await transfer(
            from: url,
            to: destination,
            allowsExpensiveNetwork: allowsExpensiveNetwork && allowsCellular(),
            onProgress: onProgress
        )
    }

    /// Transient HTTP failures are retried here; a stale URL is not, because
    /// only the resolver can replace it.
    private func transfer(
        from url: URL,
        to destination: URL,
        allowsExpensiveNetwork: Bool,
        onProgress: @escaping @Sendable (Int, Int?) -> Void
    ) async throws -> DownloadResult {
        let host = url.host ?? "none"
        let path = transferPathHash(url.path)
        var attempt = 0
        while true {
            attempt += 1
            playerLog.notice(
                "[Transfer] start kind=file host=\(host, privacy: .public) path=\(path, privacy: .public) attempt=\(attempt)"
            )
            do {
                let result = try await ProgressTransfer(
                    url: url,
                    destination: destination,
                    allowsExpensiveNetwork: allowsExpensiveNetwork,
                    onProgress: onProgress
                ).run()
                playerLog.notice(
                    "[Transfer] finish host=\(host, privacy: .public) path=\(path, privacy: .public) bytes=\(result.bytesWritten) expected=\(result.expectedBytes ?? -1)"
                )
                return result
            } catch {
                let failure = TransferFailure.classify(error)
                guard let delay = failure.retryDelay(attempt: attempt) else {
                    playerLog.error(
                        "[Transfer] failed host=\(host, privacy: .public) path=\(path, privacy: .public) reason=\(String(describing: failure), privacy: .public)"
                    )
                    throw failure
                }
                playerLog.error(
                    "[Transfer] retry host=\(host, privacy: .public) path=\(path, privacy: .public) in=\(delay) reason=\(String(describing: failure), privacy: .public)"
                )
                try await Task.sleep(for: .seconds(delay))
            }
        }
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
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 120
            configuration.httpMaximumConnectionsPerHost = 4
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            var request = URLRequest(url: url)
            request.allowsExpensiveNetworkAccess = allowsExpensiveNetwork
            request.allowsConstrainedNetworkAccess = allowsExpensiveNetwork
            request.timeoutInterval = 20
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
        guard let http = downloadTask.response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: location)
            finish(.failure(TransferFailure.other("The server returned an unexpected response.")))
            return
        }
        let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        if let failure = TransferFailure.classify(status: http.statusCode, retryAfter: retryAfter) {
            playerLog.error(
                "[Transfer] bad status=\(http.statusCode) retryAfter=\(retryAfter ?? -1) host=\(http.url?.host ?? "none", privacy: .public)"
            )
            try? FileManager.default.removeItem(at: location)
            finish(.failure(failure))
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

/// Eight hex characters of an FNV-1a hash: enough to match requests in one run
/// without writing a full path to the log.
private func transferPathHash(_ value: String) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in value.utf8 {
        hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
    }
    return String(format: "%08x", UInt32(truncatingIfNeeded: hash >> 16))
}
#endif
