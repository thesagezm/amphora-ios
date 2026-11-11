import XCTest
@testable import PandoraCore

/// The transport error's user-facing copy: the raw `reason` strings the
/// transports produce ("unreachable", "timeout", "network failure",
/// "HTTP 502", "non-HTTP response") must each map to words a user can
/// act on, and nothing else may leak into the UI.
final class TransportErrorCopyTests: XCTestCase {
    func testUnreachableCopy() {
        XCTAssertEqual(
            PandoraTransportError(reason: "unreachable").localizedDescription,
            "No internet connection. Amphora will try again."
        )
    }

    func testTimeoutCopy() {
        XCTAssertEqual(
            PandoraTransportError(reason: "timeout").localizedDescription,
            "Pandora took too long to respond. Check your connection and try again."
        )
    }

    func testNetworkFailureCopy() {
        XCTAssertEqual(
            PandoraTransportError(reason: "network failure").localizedDescription,
            "Couldn't reach Pandora. Check your connection and try again."
        )
    }

    func testHTTPSStatusCodeIsExtracted() {
        let error = PandoraTransportError(reason: "HTTP 502")
        XCTAssertEqual(error.httpStatusCode, 502)
        XCTAssertEqual(
            error.localizedDescription,
            "Pandora's servers had a problem (HTTP 502). Try again."
        )
    }

    func testHTTPReasonWithoutCodeFallsBackGenerically() {
        let error = PandoraTransportError(reason: "HTTP ")
        XCTAssertNil(error.httpStatusCode)
        XCTAssertEqual(
            error.localizedDescription,
            "Something went wrong talking to Pandora. Try again."
        )
    }

    func testUnknownReasonNeverLeaksTheRawString() {
        let error = PandoraTransportError(reason: "some internal detail")
        XCTAssertEqual(
            error.localizedDescription,
            "Something went wrong talking to Pandora. Try again."
        )
        // The raw reason stays available for the log.
        XCTAssertEqual(error.reason, "some internal detail")
    }

    func testURLErrorClassification() {
        XCTAssertEqual(PandoraTransportError(urlError: URLError(.timedOut)).reason, "timeout")
        XCTAssertEqual(
            PandoraTransportError(urlError: URLError(.notConnectedToInternet)).reason,
            "unreachable"
        )
        XCTAssertEqual(
            PandoraTransportError(urlError: URLError(.networkConnectionLost)).reason,
            "unreachable"
        )
        // Anything else is a plain network failure — a DNS miss, a TLS
        // failure, a refused connection all read the same to the user.
        XCTAssertEqual(PandoraTransportError(urlError: URLError(.dnsLookupFailed)).reason, "network failure")
    }
}
