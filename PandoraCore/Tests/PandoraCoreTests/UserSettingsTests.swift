//
//  UserSettingsTests.swift
//  PandoraCoreTests
//
//  `user.getSettings` — the account-level settings. The only field
//  Amphora uses is the explicit-content filter, which pithos reads in
//  `Pandora.explicit_content_filter_state`:
//
//      get_filter_state = self.json_call('user.getSettings', https=True)
//      filter_state = get_filter_state.get('isExplicitContentFilterEnabled', False)
//      pin_protected = get_filter_state.get('isExplicitContentFilterPINProtected', False)
//
//  (pithos' `https=True` only switches the transport to TLS — the body
//  is still Blowfish-encrypted, like every other authenticated call.)
//

import XCTest
@testable import PandoraCore

final class UserSettingsTests: XCTestCase {

    private static let clock: @Sendable () -> Date = {
        Date(timeIntervalSince1970: 1_000_000_000)
    }

    // MARK: - Decoding

    func testExplicitFilterEnabledIsDecoded() {
        let settings = UserSettings(result: [
            "isExplicitContentFilterEnabled": .bool(true),
            "isExplicitContentFilterPINProtected": .bool(false)
        ])
        XCTAssertTrue(settings.isExplicitContentFilterEnabled)
        XCTAssertFalse(settings.isExplicitContentFilterPINProtected)
    }

    func testExplicitFilterDisabledIsDecoded() {
        let settings = UserSettings(result: [
            "isExplicitContentFilterEnabled": .bool(false)
        ])
        XCTAssertFalse(settings.isExplicitContentFilterEnabled)
    }

    func testPinProtectedStateIsDecoded() {
        let settings = UserSettings(result: [
            "isExplicitContentFilterEnabled": .bool(true),
            "isExplicitContentFilterPINProtected": .bool(true)
        ])
        XCTAssertTrue(settings.isExplicitContentFilterPINProtected)
    }

    func testMissingKeysMeanTheFilterIsOff() {
        // pithos reads the field with a `False` default — an older
        // server that does not send the key must not be read as "the
        // filter is on".
        let settings = UserSettings(result: [:])
        XCTAssertFalse(settings.isExplicitContentFilterEnabled)
        XCTAssertFalse(settings.isExplicitContentFilterPINProtected)
    }

    func testWrongTypeIsTreatedAsOff() {
        let settings = UserSettings(result: [
            "isExplicitContentFilterEnabled": .string("true")
        ])
        XCTAssertFalse(settings.isExplicitContentFilterEnabled)
    }

    // MARK: - The call

    func testGetUserSettingsSendsTheMethodAndDecodesTheReply() async throws {
        let store = InMemorySessionStore(record: SessionRecord(
            credentials: Credentials(username: "me@example.com", password: "hunter2"),
            tokens: SessionTokens(
                partnerId: "77",
                partnerAuthToken: "P-TOKEN",
                userId: "u-1",
                userAuthToken: "U-LISTED",
                timeOffset: 760_000_000
            ),
            isSubscriber: false
        ))
        let transport = MockTransport(responses: [
            .success(Data("{\"stat\":\"ok\",\"result\":{\"isExplicitContentFilterEnabled\":true,\"isExplicitContentFilterPINProtected\":false}}".utf8))
        ])
        let subject = SessionManager(
            client: LegacyPandoraClient(transport: transport),
            store: store,
            now: Self.clock
        )
        let restored = await subject.restore()
        XCTAssertTrue(restored)

        let settings = try await subject.getUserSettings()
        XCTAssertTrue(settings.isExplicitContentFilterEnabled)
        XCTAssertFalse(settings.isExplicitContentFilterPINProtected)

        let requests = transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertTrue(request.url.absoluteString.contains("method=user.getSettings"))
        XCTAssertTrue(request.url.absoluteString.contains("auth_token=U-LISTED"))
    }

    func testGetUserSettingsReAuthsOnAnExpiredSession() async throws {
        // The same 1001 contract as every other authenticated call.
        let store = InMemorySessionStore(record: SessionRecord(
            credentials: Credentials(username: "me@example.com", password: "hunter2"),
            tokens: SessionTokens(
                partnerId: "77",
                partnerAuthToken: "P-TOKEN",
                userId: "u-1",
                userAuthToken: "U-EXPIRED",
                timeOffset: 760_000_000
            ),
            isSubscriber: false
        ))
        let transport = MockTransport(responses: [
            .success(Data("{\"stat\":\"fail\",\"code\":1001,\"message\":\"Invalid auth token\"}".utf8)),
            .success(Data("{\"stat\":\"ok\",\"result\":{\"partnerId\":\"77\",\"partnerAuthToken\":\"P-TOKEN\",\"syncTime\":\"ac7b93e6a3c44c45258042bca01c9f6f40befffb546dee73\"}}".utf8)),
            .success(Data("{\"stat\":\"ok\",\"result\":{\"userId\":\"u-1\",\"userAuthToken\":\"U-FRESH\",\"isSubscriber\":true}}".utf8)),
            .success(Data("{\"stat\":\"ok\",\"result\":{\"isExplicitContentFilterEnabled\":false}}".utf8))
        ])
        let subject = SessionManager(
            client: LegacyPandoraClient(transport: transport),
            store: store,
            now: Self.clock
        )
        let restored = await subject.restore()
        XCTAssertTrue(restored)

        let settings = try await subject.getUserSettings()
        XCTAssertFalse(settings.isExplicitContentFilterEnabled)

        let requests = transport.requests
        XCTAssertEqual(requests.count, 4, "original, partner, user, replay")
        XCTAssertTrue(requests[3].url.absoluteString.contains("auth_token=U-FRESH"))
    }
}
