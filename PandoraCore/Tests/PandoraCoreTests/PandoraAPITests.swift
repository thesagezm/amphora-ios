import XCTest
@testable import PandoraCore

final class PandoraAPITests: XCTestCase {

    func testBaseURLIsTheLegacyJSONRPCEndpoint() throws {
        XCTAssertEqual(PandoraAPI.baseURL.scheme, "https")
        XCTAssertEqual(PandoraAPI.baseURL.host, "tuner.pandora.com")
        XCTAssertEqual(PandoraAPI.baseURL.path, "/services/json/")
    }

    func testMethodNamesMatchTheLegacyProtocol() {
        XCTAssertEqual(PandoraAPI.Method.partnerLogin, "auth.partnerLogin")
        XCTAssertEqual(PandoraAPI.Method.userLogin, "auth.userLogin")
    }
}
