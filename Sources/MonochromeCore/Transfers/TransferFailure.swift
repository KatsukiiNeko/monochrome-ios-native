// TransferFailure.swift: what went wrong with one HTTP transfer, and how to react.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A classified HTTP or transport failure. The point is that a caller can retry
/// what is transient and explain what is not, instead of surfacing a bare
/// `URLError` (`-1011` is the generic "bad response" that hides all of these).
public enum TransferFailure: Error, Equatable, LocalizedError, Sendable {
    /// The stream URL or session is no longer valid. Resolve a fresh URL once.
    case expiredOrForbidden(Int)
    case notFound
    /// The origin refused the requested byte range; restart from the first byte.
    case rangeNotSatisfiable
    case rateLimited(retryAfter: TimeInterval?)
    case server(Int)
    case unexpected(Int)
    case timedOut
    case offline
    case connectionLost
    case other(String)

    /// Classifies an HTTP status; nil means the response is acceptable.
    public static func classify(status: Int, retryAfter: TimeInterval? = nil) -> TransferFailure? {
        switch status {
        case 200..<300: return nil
        case 401, 403: return .expiredOrForbidden(status)
        case 404: return .notFound
        case 416: return .rangeNotSatisfiable
        case 429: return .rateLimited(retryAfter: retryAfter)
        case 500..<600: return .server(status)
        default: return .unexpected(status)
        }
    }

    /// Classifies a transport error. `-1011` is deliberately not treated as a
    /// server failure of its own: the HTTP status above is more precise.
    public static func classify(_ error: any Error) -> TransferFailure {
        if let failure = error as? TransferFailure { return failure }
        guard let urlError = error as? URLError else { return .other(error.localizedDescription) }
        switch urlError.code {
        case .timedOut: return .timedOut
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: return .offline
        case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return .connectionLost
        default: return .other(urlError.localizedDescription)
        }
    }

    /// How long to wait before the next attempt, or nil when this failure is final.
    /// `attempt` counts the attempts already made, starting at 1.
    public func retryDelay(attempt: Int, maximumAttempts: Int = 3) -> TimeInterval? {
        guard attempt < maximumAttempts else { return nil }
        switch self {
        case .rateLimited(let stated): return stated ?? Self.backoff(attempt)
        case .server, .timedOut, .connectionLost: return Self.backoff(attempt)
        case .expiredOrForbidden, .notFound, .rangeNotSatisfiable, .offline, .unexpected, .other:
            return nil
        }
    }

    private static func backoff(_ attempt: Int) -> TimeInterval {
        [0.5, 1.0, 2.0][min(max(attempt - 1, 0), 2)]
    }

    public var errorDescription: String? {
        switch self {
        case .expiredOrForbidden:
            "This track's link has expired. Play it again to get a fresh one."
        case .notFound:
            "This track is no longer available from the source."
        case .rangeNotSatisfiable:
            "The source refused to resume the download. Try again."
        case .rateLimited:
            "The service is busy. Try again in a moment."
        case .server(let code):
            "The service had a problem (HTTP \(code)). Try again later."
        case .unexpected(let code):
            "The source answered with HTTP \(code)."
        case .timedOut:
            "The connection timed out. Check the network, then retry."
        case .offline:
            "You appear to be offline. Check the connection, then retry."
        case .connectionLost:
            "The connection was lost. Check the network, then retry."
        case .other(let message):
            message
        }
    }
}
