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

    func testAndroidGenericClientConstantsMatchPithosReference() {
        // pithos/pandora/data.py, client_keys['android-generic']
        XCTAssertEqual(PandoraAPI.partnerUsername, "android")
        XCTAssertEqual(PandoraAPI.partnerPassword, "AC7IBG09A3DTSYM4R41UJWL07VLN8JI7")
        XCTAssertEqual(PandoraAPI.partnerDeviceModel, "android-generic")
        XCTAssertEqual(PandoraAPI.version, "5")
        XCTAssertEqual(PandoraAPI.encryptKey, "6#26FRL$ZWD")
        XCTAssertEqual(PandoraAPI.decryptKey, "R=U!LH$O2B#")
    }
}
