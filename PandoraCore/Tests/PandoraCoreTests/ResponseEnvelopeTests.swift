//
//  ResponseEnvelopeTests.swift
//  PandoraCoreTests
//

import XCTest
@testable import PandoraCore

final class ResponseEnvelopeTests: XCTestCase {

    func testOkEnvelopeReturnsResult() throws {
        let payload = Data(#"{"stat":"ok","result":{"partnerId":"123","partnerAuthToken":"PT"}}"#.utf8)
        let result = try ResponseEnvelope.result(from: payload)
        XCTAssertEqual(try result.string("partnerId"), "123")
        XCTAssertEqual(try result.string("partnerAuthToken"), "PT")
    }

    func testFailEnvelopeThrowsTypedAPIError() {
        let payload = Data(#"{"stat":"fail","code":1002,"message":"Invalid username or password"}"#.utf8)
        XCTAssertThrowsError(try ResponseEnvelope.result(from: payload)) { error in
            let apiError = error as? PandoraAPIError
            XCTAssertEqual(apiError?.code, 1002)
            XCTAssertEqual(apiError?.message, "Invalid username or password")
            XCTAssertTrue(apiError?.isInvalidCredentials == true)
            XCTAssertFalse(apiError?.isSessionExpired == true)
        }
    }

    func testInvalidAuthTokenIsSessionExpiry() {
        let payload = Data(#"{"stat":"fail","code":1001,"message":"auth token invalid"}"#.utf8)
        XCTAssertThrowsError(try ResponseEnvelope.result(from: payload)) { error in
            XCTAssertTrue((error as? PandoraAPIError)?.isSessionExpired == true)
        }
    }

    func testUndocumentedCodeStillTyped() {
        let payload = Data(#"{"stat":"fail","code":9999,"message":"mystery"}"#.utf8)
        XCTAssertThrowsError(try ResponseEnvelope.result(from: payload)) { error in
            guard let apiError = error as? PandoraAPIError else {
                return XCTFail("expected PandoraAPIError, got \(error)")
            }
            XCTAssertEqual(apiError.code, 9999)
            XCTAssertEqual(apiError.localizedDescription, "Pandora error 9999: mystery")
        }
    }

    func testMalformedBodyIsTypedError() {
        XCTAssertThrowsError(try ResponseEnvelope.result(from: Data("not json".utf8))) { error in
            XCTAssertNotNil(error as? PandoraMalformedResponseError)
        }
    }

    func testOkWithoutResultIsTypedError() {
        let payload = Data(#"{"stat":"ok"}"#.utf8)
        XCTAssertThrowsError(try ResponseEnvelope.result(from: payload)) { error in
            XCTAssertNotNil(error as? PandoraMalformedResponseError)
        }
    }

    func testUnknownStatIsTypedError() {
        let payload = Data(#"{"stat":"weird","result":{}}"#.utf8)
        XCTAssertThrowsError(try ResponseEnvelope.result(from: payload)) { error in
            XCTAssertNotNil(error as? PandoraMalformedResponseError)
        }
    }

    func testFriendlyMessagesForCuratedCodes() {
        let invalidLogin = PandoraAPIError(code: 1002, message: "server said no")
        XCTAssertEqual(invalidLogin.localizedDescription, "Invalid username or password.")
        let maintenance = PandoraAPIError(code: 1, message: "maintenance")
        XCTAssertTrue(maintenance.localizedDescription.contains("maintenance"))
    }
}
