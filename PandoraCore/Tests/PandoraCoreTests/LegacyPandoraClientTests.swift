//
//  LegacyPandoraClientTests.swift
//  PandoraCoreTests
//
//  Transport-level tests with a mock `HTTPTransport`: request shape
//  (URL query, body, content type) and response unwrapping — no network.
//

import XCTest
@testable import PandoraCore

final class LegacyPandoraClientTests: XCTestCase {

    private let fixedNow = Date(timeIntervalSince1970: 1_000_000_000)

    func testPartnerLoginSendsPlainJSONBodyWithoutAuthQuery() async throws {
        let fixture = Data(#"{"stat":"ok","result":{"stat":"ok","partnerId":"77","partnerAuthToken":"P-TOKEN","syncTime":"ac7b93e6a3c44c45258042bca01c9f6f40befffb546dee73"}}"#.utf8)
        let transport = MockTransport(responses: [.success(fixture)])
        let client = LegacyPandoraClient(transport: transport)

        let result = try await client.request(
            method: PandoraAPI.Method.partnerLogin,
            parameters: [
                "username": .string(PandoraAPI.partnerUsername),
                "password": .string(PandoraAPI.partnerPassword),
                "deviceModel": .string(PandoraAPI.partnerDeviceModel),
                "version": .string(PandoraAPI.version)
            ],
            encrypt: false,
            now: fixedNow
        )

        XCTAssertEqual(try result.string("partnerId"), "77")
        XCTAssertEqual(try result.string("partnerAuthToken"), "P-TOKEN")

        let recorded = transport.requests
        XCTAssertEqual(recorded.count, 1)
        let request = try XCTUnwrap(recorded.first)

        // Query: only `method` before partner login completes.
        XCTAssertEqual(
            request.url.absoluteString,
            "https://tuner.pandora.com/services/json/?method=auth.partnerLogin"
        )
        XCTAssertEqual(request.contentType, "application/json")
        XCTAssertEqual(
            String(decoding: request.body, as: UTF8.self),
            #"{"deviceModel":"android-generic","password":"AC7IBG09A3DTSYM4R41UJWL07VLN8JI7","username":"android","version":"5"}"#
        )
    }

    func testUserLoginSendsEncryptedBodyWithPartnerTokenAndSyncTime() async throws {
        let fixture = Data(#"{"stat":"ok","result":{"userId":"u-1","userAuthToken":"U-TOKEN","isSubscriber":false}}"#.utf8)
        let transport = MockTransport(responses: [.success(fixture)])

        var context = URLBuilder.Context()
        context.partnerId = "77"
        context.partnerAuthToken = "P-TOKEN"
        context.timeOffset = 760_000_000   // pandora_time 1_760_000_000 − now 1_000_000_000

        let client = LegacyPandoraClient(
            transport: transport,
            builder: URLBuilder(context: context)
        )

        let result = try await client.request(
            method: PandoraAPI.Method.userLogin,
            parameters: [
                "username": .string("me@example.com"),
                "password": .string("hunter2"),
                "loginType": .string("user"),
                "returnIsSubscriber": .bool(true)
            ],
            now: fixedNow
        )
        XCTAssertEqual(try result.string("userAuthToken"), "U-TOKEN")
        XCTAssertEqual(try result.bool("isSubscriber"), false)

        let recorded = transport.requests
        let request = try XCTUnwrap(recorded.first)

        // Query carries partner_id + partner auth_token.
        XCTAssertEqual(
            request.url.absoluteString,
            "https://tuner.pandora.com/services/json/?partner_id=77&auth_token=P-TOKEN&method=auth.userLogin"
        )
        XCTAssertEqual(request.contentType, "text/plain")

        // Body is Blowfish hex; decrypting recovers the expected JSON.
        let hex = String(decoding: request.body, as: UTF8.self)
        XCTAssertTrue(hex.allSatisfy(\.isHexDigit))
        let json = try PandoraCrypto.decryptFromHex(hex, key: PandoraAPI.encryptKey)
        XCTAssertEqual(
            String(decoding: json, as: UTF8.self),
            #"{"loginType":"user","partnerAuthToken":"P-TOKEN","password":"hunter2","returnIsSubscriber":true,"syncTime":1760000000,"username":"me@example.com"}"#
        )
    }

    func testFaultPropagatesAsTypedError() async {
        let fixture = Data(#"{"stat":"fail","code":1001,"message":"Invalid auth token"}"#.utf8)
        let transport = MockTransport(responses: [.success(fixture)])
        let client = LegacyPandoraClient(transport: transport)

        do {
            _ = try await client.request(method: "user.getStationList")
            XCTFail("expected PandoraAPIError")
        } catch let error as PandoraAPIError {
            XCTAssertTrue(error.isSessionExpired)
            XCTAssertEqual(error.code, 1001)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testTransportFailurePropagates() async {
        let transport = MockTransport(responses: [
            .failure(PandoraTransportError(reason: "HTTP 503"))
        ])
        let client = LegacyPandoraClient(transport: transport)

        do {
            _ = try await client.request(method: PandoraAPI.Method.partnerLogin, encrypt: false)
            XCTFail("expected transport error")
        } catch let error as PandoraTransportError {
            XCTAssertEqual(error.reason, "HTTP 503")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testAuthTokenWithReservedCharactersIsPercentEncoded() async throws {
        let fixture = Data(#"{"stat":"ok","result":{}}"#.utf8)
        let transport = MockTransport(responses: [.success(fixture)])

        var context = URLBuilder.Context()
        context.partnerId = "77"
        context.partnerAuthToken = "aZ+0/9="
        let client = LegacyPandoraClient(transport: transport, builder: URLBuilder(context: context))

        _ = try await client.request(method: "user.getStationList")

        let recorded = transport.requests
        let request = try XCTUnwrap(recorded.first)
        XCTAssertEqual(
            request.url.absoluteString,
            "https://tuner.pandora.com/services/json/?partner_id=77&auth_token=aZ%2B0%2F9%3D&method=user.getStationList"
        )
    }
}
