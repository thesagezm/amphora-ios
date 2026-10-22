//
//  URLBuilderTests.swift
//  PandoraCoreTests
//
//  URL/param building must match `pithos.pandora.Pandora.json_call`
//  byte-for-byte (query order, token precedence, syncTime injection,
//  deterministic sorted-key JSON, encryption on/off per method).
//

import XCTest
@testable import PandoraCore

final class URLBuilderTests: XCTestCase {

    private let fixedNow = Date(timeIntervalSince1970: 1_000_000_000)

    private func builder(
        partnerId: String? = nil,
        partnerAuthToken: String? = nil,
        userId: String? = nil,
        userAuthToken: String? = nil,
        timeOffset: TimeInterval? = nil
    ) -> URLBuilder {
        URLBuilder(context: URLBuilder.Context(
            partnerId: partnerId,
            partnerAuthToken: partnerAuthToken,
            userId: userId,
            userAuthToken: userAuthToken,
            timeOffset: timeOffset
        ))
    }

    // MARK: - Query string

    func testPartnerLoginURLHasOnlyMethod() throws {
        let url = try builder().endpointURL(method: PandoraAPI.Method.partnerLogin)
        XCTAssertEqual(
            url.absoluteString,
            "https://tuner.pandora.com/services/json/?method=auth.partnerLogin"
        )
    }

    func testQueryOrderIsPartnerIdUserIdAuthTokenMethod() throws {
        let url = try builder(
            partnerId: "123",
            userId: "u-9",
            userAuthToken: "UT"
        ).endpointURL(method: "user.getStationList")
        XCTAssertEqual(
            url.absoluteString,
            "https://tuner.pandora.com/services/json/?partner_id=123&user_id=u-9&auth_token=UT&method=user.getStationList"
        )
    }

    func testUserTokenTakesPrecedenceOverPartnerToken() throws {
        let url = try builder(
            partnerId: "123",
            partnerAuthToken: "PT",
            userAuthToken: "UT"
        ).endpointURL(method: "station.getPlaylist")
        XCTAssertTrue(url.absoluteString.contains("auth_token=UT"))
        XCTAssertFalse(url.absoluteString.contains("PT"))
    }

    func testPartnerTokenUsedBeforeUserLogin() throws {
        let url = try builder(
            partnerId: "123",
            partnerAuthToken: "PT"
        ).endpointURL(method: PandoraAPI.Method.userLogin)
        XCTAssertEqual(
            url.absoluteString,
            "https://tuner.pandora.com/services/json/?partner_id=123&auth_token=PT&method=auth.userLogin"
        )
    }

    // MARK: - Body: partnerLogin (plain JSON, no session fields yet)

    func testPartnerLoginBodyIsPlainSortedJSON() throws {
        let body = try builder().requestBody(parameters: [
            "username": .string(PandoraAPI.partnerUsername),
            "password": .string(PandoraAPI.partnerPassword),
            "deviceModel": .string(PandoraAPI.partnerDeviceModel),
            "version": .string(PandoraAPI.version)
        ], encrypt: false, now: fixedNow)
        XCTAssertEqual(
            String(decoding: body, as: UTF8.self),
            #"{"deviceModel":"android-generic","password":"AC7IBG09A3DTSYM4R41UJWL07VLN8JI7","username":"android","version":"5"}"#
        )
    }

    // MARK: - Body: session fields

    func testSyncTimeInjectedWhenOffsetKnown() throws {
        let body = try builder(partnerId: "123", timeOffset: 123.5).requestBody(
            parameters: ["username": .string("u")],
            encrypt: false,
            now: fixedNow
        )
        // Int(now + offset) truncates like Python int(): 1_000_000_123.5 → 1_000_000_123
        XCTAssertEqual(
            String(decoding: body, as: UTF8.self),
            #"{"syncTime":1000000123,"username":"u"}"#
        )
    }

    func testNoSyncTimeBeforeOffsetIsKnown() throws {
        let body = try builder().requestBody(
            parameters: ["username": .string("u")],
            encrypt: false,
            now: fixedNow
        )
        XCTAssertEqual(String(decoding: body, as: UTF8.self), #"{"username":"u"}"#)
    }

    func testPartnerAuthTokenMergedIntoBody() throws {
        let body = try builder(partnerAuthToken: "PT").requestBody(
            parameters: ["username": .string("u")],
            encrypt: false,
            now: fixedNow
        )
        XCTAssertEqual(
            String(decoding: body, as: UTF8.self),
            #"{"partnerAuthToken":"PT","username":"u"}"#
        )
    }

    func testUserAuthTokenWinsOverPartnerAuthTokenInBody() throws {
        let body = try builder(
            partnerAuthToken: "PT",
            userAuthToken: "UT"
        ).requestBody(parameters: [:], encrypt: false, now: fixedNow)
        XCTAssertEqual(String(decoding: body, as: UTF8.self), #"{"userAuthToken":"UT"}"#)
    }

    // MARK: - Body: encryption (userLogin path)

    func testEncryptedBodyRoundTripsToExpectedJSON() throws {
        let b = builder(partnerId: "123", partnerAuthToken: "PT", timeOffset: 0)
        let body = try b.requestBody(parameters: [
            "username": .string("me@example.com"),
            "password": .string("hunter2"),
            "loginType": .string("user"),
            "returnIsSubscriber": .bool(true)
        ], encrypt: true, now: fixedNow)

        // Output is hex, not JSON.
        let hex = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(hex.allSatisfy { $0.isHexDigit }, "body must be hex, got \(hex.prefix(32))…")

        // Decrypting with the same key recovers the expected JSON. Trailing
        // zero-padding from the per-chunk pad survives decryption — trim it
        // for comparison (callers do the same for syncTime fields).
        let decrypted = try PandoraCrypto.decryptFromHex(hex, key: PandoraAPI.encryptKey)
        let trimmed = decrypted.prefix { $0 != 0 }
        XCTAssertEqual(
            String(decoding: trimmed, as: UTF8.self),
            #"{"loginType":"user","partnerAuthToken":"PT","password":"hunter2","returnIsSubscriber":true,"syncTime":1000000000,"username":"me@example.com"}"#
        )
    }

    // MARK: - Escaping

    func testStringEscapingInJSONBody() throws {
        let body = try builder().requestBody(
            parameters: ["note": .string(#"say "hi"\path"# + "\n")],
            encrypt: false,
            now: fixedNow
        )
        XCTAssertEqual(
            String(decoding: body, as: UTF8.self),
            #"{"note":"say \"hi\"\\path\n"}"#
        )
    }

    func testControlCharacterEscapedAsUnicode() throws {
        let body = try builder().requestBody(
            parameters: ["note": .string("\u{01}")],
            encrypt: false,
            now: fixedNow
        )
        XCTAssertEqual(String(decoding: body, as: UTF8.self), #"{"note":"\u0001"}"#)
    }

    func testBoolAndIntLiterals() throws {
        let body = try builder().requestBody(
            parameters: ["a": .bool(false), "b": .int(42)],
            encrypt: false,
            now: fixedNow
        )
        XCTAssertEqual(String(decoding: body, as: UTF8.self), #"{"a":false,"b":42}"#)
    }
}
