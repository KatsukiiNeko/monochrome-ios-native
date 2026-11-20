// TransferFailureTests.swift: HTTP classification and retry policy.
import Foundation
import Testing
@testable import MonochromeCore

@Suite("Transfer failure policy")
struct TransferFailureTests {
    @Test func successStatusIsNotAFailure() {
        #expect(TransferFailure.classify(status: 200) == nil)
        #expect(TransferFailure.classify(status: 206) == nil)
    }

    @Test func statusesAreClassified() {
        #expect(TransferFailure.classify(status: 403) == .expiredOrForbidden(403))
        #expect(TransferFailure.classify(status: 404) == .notFound)
        #expect(TransferFailure.classify(status: 416) == .rangeNotSatisfiable)
        #expect(TransferFailure.classify(status: 429) == .rateLimited(retryAfter: nil))
        #expect(TransferFailure.classify(status: 503) == .server(503))
        #expect(TransferFailure.classify(status: 418) == .unexpected(418))
    }

    @Test func retryAfterIsHonoured() {
        let failure = TransferFailure.classify(status: 429, retryAfter: 12)
        #expect(failure?.retryDelay(attempt: 1) == 12)
    }

    @Test func transientFailuresBackOffAndStop() {
        let server = TransferFailure.server(502)
        #expect(server.retryDelay(attempt: 1) == 0.5)
        #expect(server.retryDelay(attempt: 2) == 1.0)
        #expect(server.retryDelay(attempt: 3) == nil)
        #expect(TransferFailure.rateLimited(retryAfter: nil).retryDelay(attempt: 1) == 0.5)
        #expect(TransferFailure.timedOut.retryDelay(attempt: 2) == 1.0)
    }

    @Test func permanentFailuresDoNotRetry() {
        #expect(TransferFailure.notFound.retryDelay(attempt: 1) == nil)
        #expect(TransferFailure.expiredOrForbidden(401).retryDelay(attempt: 1) == nil)
        #expect(TransferFailure.offline.retryDelay(attempt: 1) == nil)
        #expect(TransferFailure.unexpected(418).retryDelay(attempt: 1) == nil)
    }

    @Test func transportErrorsAreClassified() {
        #expect(TransferFailure.classify(URLError(.timedOut)) == .timedOut)
        #expect(TransferFailure.classify(URLError(.notConnectedToInternet)) == .offline)
        #expect(TransferFailure.classify(URLError(.networkConnectionLost)) == .connectionLost)
        #expect(TransferFailure.classify(URLError(.badServerResponse)) == .other(URLError(.badServerResponse).localizedDescription))
    }
}
