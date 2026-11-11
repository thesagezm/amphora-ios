import XCTest
@testable import PandoraCore

/// The transport's own timeout: the system default leaves the resource
/// timeout at seven days, so a connection that was accepted but never
/// answers would hang the request — and the UI — effectively forever.
/// `makeRequest(url:body:contentType:)` is pure, so these assert the
/// wire shape without a network.
final class TransportTimeoutTests: XCTestCase {
    private let url = URL(string: "https://tuner.pandora.com/services/json/")!

    func testRequestCarriesTheDefaultTimeout() {
        let transport = URLSessionTransport(session: .shared, userAgent: "Amphora")
        let request = transport.makeRequest(
            url: url, body: Data(), contentType: "application/x-www-form-urlencoded"
        )
        XCTAssertEqual(request.timeoutInterval, URLSessionTransport.defaultTimeoutInterval)
        XCTAssertEqual(URLSessionTransport.defaultTimeoutInterval, 30)
    }

    func testCustomTimeoutIsHonored() {
        let transport = URLSessionTransport(
            session: .shared, userAgent: "Amphora", timeoutInterval: 8
        )
        let request = transport.makeRequest(
            url: url, body: Data(), contentType: "application/json"
        )
        XCTAssertEqual(request.timeoutInterval, 8)
    }

    func testRequestAssemblyIsUnchanged() {
        let transport = URLSessionTransport(session: .shared, userAgent: "Amphora")
        let body = Data("enc=payload".utf8)
        let request = transport.makeRequest(
            url: url, body: body, contentType: "application/x-www-form-urlencoded"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"),
                       "application/x-www-form-urlencoded")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Amphora")
        XCTAssertEqual(request.httpBody, body)
    }

    func testTimeoutIsWellBounded() {
        // A hang must recover inside a human attention span, and a
        // legitimate fetch (slow cellular playlist) must not time out.
        let interval = URLSessionTransport.defaultTimeoutInterval
        XCTAssertGreaterThanOrEqual(interval, 15)
        XCTAssertLessThanOrEqual(interval, 60)
    }

    func testMainTransportSharesThePackageDefault() {
        // The main transport and the shared constant must not drift
        // apart — every other transport (lyrics GET, Last.fm, station
        // modes, CSRF bootstrap, the app's artwork cache) applies
        // NetworkDefaults.requestTimeoutInterval directly.
        XCTAssertEqual(
            URLSessionTransport.defaultTimeoutInterval,
            NetworkDefaults.requestTimeoutInterval
        )
        XCTAssertGreaterThan(NetworkDefaults.requestTimeoutInterval, 0)
    }
}
