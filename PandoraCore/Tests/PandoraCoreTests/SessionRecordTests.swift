//
//  SessionRecordTests.swift
//  PandoraCoreTests
//
//  Codable round-trip for the persisted session record (what the app's
//  Keychain store encodes) plus InMemorySessionStore semantics. A key
//  rename here would strand existing installs' stored sessions and break
//  warm-launch auto-login, so the literal fixture is load-bearing.
//

import XCTest
@testable import PandoraCore

final class SessionRecordTests: XCTestCase {

    private let record = SessionRecord(
        credentials: Credentials(username: "me@example.com", password: "hunter2"),
        tokens: SessionTokens(
            partnerId: "77",
            partnerAuthToken: "P-TOKEN",
            userId: "u-1",
            userAuthToken: "U-TOKEN",
            timeOffset: 760_000_000.5
        ),
        isSubscriber: true
    )

    func testSessionRecordEncodesAndDecodesLosslessly() throws {
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: data)
        XCTAssertEqual(decoded, record)
    }

    func testSessionRecordDecodesFromFixedJSONFixture() throws {
        // Exact shape the Keychain store persists today. Decoding a literal
        // guards against a synthesized-Codable property rename, which would
        // silently discard stored sessions on upgrade.
        let json = """
        {"credentials":{"username":"me@example.com","password":"hunter2"},\
        "tokens":{"partnerId":"77","partnerAuthToken":"P-TOKEN","userId":"u-1",\
        "userAuthToken":"U-TOKEN","timeOffset":760000000.5},\
        "isSubscriber":true}
        """
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, record)
    }

    func testInMemorySessionStoreSaveLoadClear() throws {
        let store = InMemorySessionStore()
        XCTAssertNil(store.load())
        try store.save(record)
        XCTAssertEqual(store.load(), record)
        try store.clear()
        XCTAssertNil(store.load())
    }
}
